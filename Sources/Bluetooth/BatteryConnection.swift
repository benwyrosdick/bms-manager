import Foundation
import CoreBluetooth
import Combine

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case discovering
    case ready
    case failed(String)
}

struct DiscoveredService: Identifiable, Equatable {
    var id: String { uuid.uuidString }
    let uuid: CBUUID
    let characteristicUUIDs: [CBUUID]
}

@MainActor
final class BatteryConnection: NSObject, ObservableObject, Identifiable {
    nonisolated let peripheral: CBPeripheral
    nonisolated var id: UUID { peripheral.identifier }
    nonisolated var peripheralIDString: String { peripheral.identifier.uuidString }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var stats: BatteryStats?
    @Published private(set) var lastError: String?
    @Published private(set) var discoveredServices: [DiscoveredService] = []
    @Published private(set) var matchedServiceUUID: CBUUID?
    @Published private(set) var lastFrameBytes: Data?
    @Published private(set) var pollEnabled: Bool = true

    private weak var central: CBCentralManager?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private let assembler = JBDFrameAssembler()
    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 3.0
    private let log = BLELogger.shared

    init(peripheral: CBPeripheral, central: CBCentralManager) {
        self.peripheral = peripheral
        self.central = central
        super.init()
        peripheral.delegate = self
    }

    // MARK: - Public controls

    func connect() {
        guard let central else { return }
        guard state != .connecting && state != .ready && state != .discovering else { return }
        state = .connecting
        log.log("Connect requested", category: .connect, peripheral: peripheralIDString)
        central.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        if let central {
            central.cancelPeripheralConnection(peripheral)
        }
        state = .disconnected
        log.log("Disconnect requested", category: .connect, peripheral: peripheralIDString)
    }

    func reconnect() {
        log.log("Reconnect requested", category: .connect, peripheral: peripheralIDString)
        disconnect()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.connect()
        }
    }

    func setPolling(_ enabled: Bool) {
        pollEnabled = enabled
        if enabled, state == .ready { startPolling() } else { pollTask?.cancel(); pollTask = nil }
    }

    /// Manually send the basic-info command. Useful from the debug UI.
    func sendBasicInfoNow() {
        requestBasicInfo()
    }

    /// Manually send the cell-voltages command. Response is logged but not parsed yet.
    func sendCellVoltagesNow() {
        guard let writeCharacteristic else {
            log.log("Cannot write: no write characteristic", level: .warn, category: .write, peripheral: peripheralIDString)
            return
        }
        let type = writeType(for: writeCharacteristic)
        log.log("→ cell voltages cmd: \(JBDProtocol.cellVoltagesCommand.hexLog)", category: .write, peripheral: peripheralIDString)
        peripheral.writeValue(JBDProtocol.cellVoltagesCommand, for: writeCharacteristic, type: type)
    }

    // MARK: - Central callbacks

    func handleConnected() {
        state = .discovering
        assembler.reset()
        log.log("Discovering services (all)", category: .discover, peripheral: peripheralIDString)
        // Discover all services rather than only FF00 — some BMS vendors expose
        // the same characteristic shape on a custom service UUID.
        peripheral.discoverServices(nil)
    }

    func handleDisconnected(error: Error?) {
        pollTask?.cancel()
        pollTask = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        matchedServiceUUID = nil
        if let error {
            state = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        } else {
            state = .disconnected
        }
    }

    // MARK: - Internals

    private func writeType(for characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
    }

    private func startPolling() {
        pollTask?.cancel()
        guard pollEnabled else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.requestBasicInfo()
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
            }
        }
    }

    private func requestBasicInfo() {
        guard let writeCharacteristic else {
            log.log("Cannot poll: no write characteristic", level: .warn, category: .write, peripheral: peripheralIDString)
            return
        }
        let type = writeType(for: writeCharacteristic)
        log.log("→ basic info cmd: \(JBDProtocol.basicInfoCommand.hexLog) (\(type == .withoutResponse ? "noResp" : "resp"))",
                level: .debug, category: .write, peripheral: peripheralIDString)
        peripheral.writeValue(JBDProtocol.basicInfoCommand, for: writeCharacteristic, type: type)
    }

    private func handleFrame(_ frame: Data) {
        lastFrameBytes = frame
        log.log("← frame \(frame.hexLog)", level: .debug, category: .frame, peripheral: peripheralIDString)
        do {
            let (cmd, payload) = try JBDProtocol.payload(of: frame)
            switch cmd {
            case 0x03:
                let info = try JBDProtocol.decodeBasicInfo(payload: payload)
                stats = BatteryStats(
                    voltage: info.totalVoltage,
                    current: info.current,
                    stateOfCharge: info.stateOfCharge,
                    remainingCapacityAh: info.remainingCapacityAh,
                    nominalCapacityAh: info.nominalCapacityAh,
                    cycleCount: info.cycleCount,
                    temperaturesC: info.temperaturesC,
                    chargeFETOn: info.chargeFETOn,
                    dischargeFETOn: info.dischargeFETOn,
                    cellCount: info.cellCount,
                    timestamp: .now
                )
                lastError = nil
                log.log("Basic info: \(String(format: "%.2fV %+.2fA %.0f%% cycles=%d", info.totalVoltage, info.current, info.stateOfCharge, info.cycleCount))",
                        category: .frame, peripheral: peripheralIDString)
            case 0x04:
                log.log("Cell voltages payload (\(payload.count)B): \(payload.hexLog)",
                        category: .frame, peripheral: peripheralIDString)
            default:
                log.log("Unhandled cmd 0x\(String(cmd, radix: 16)) (\(payload.count)B)",
                        level: .warn, category: .frame, peripheral: peripheralIDString)
            }
        } catch {
            lastError = "Frame decode failed: \(error)"
            log.log("Decode error: \(error)", level: .error, category: .frame, peripheral: peripheralIDString)
        }
    }
}

extension BatteryConnection: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        Task { @MainActor in
            if let error {
                self.log.log("Service discovery error: \(error.localizedDescription)",
                             level: .error, category: .discover, peripheral: self.peripheralIDString)
                self.state = .failed(error.localizedDescription)
                return
            }
            self.log.log("Discovered \(services.count) services: [\(services.map { $0.uuid.uuidString }.joined(separator: ","))]",
                         category: .discover, peripheral: self.peripheralIDString)
            // Discover characteristics for every service; we'll pick the one
            // that exposes both notify (FF01) and write (FF02).
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let chars = service.characteristics ?? []
        let summary = chars.map { ch -> String in
            "\(ch.uuid.uuidString)[\(ch.properties.summary)]"
        }.joined(separator: ", ")

        Task { @MainActor in
            if let error {
                self.log.log("Char discovery error on \(service.uuid.uuidString): \(error.localizedDescription)",
                             level: .error, category: .discover, peripheral: self.peripheralIDString)
                return
            }
            self.log.log("\(service.uuid.uuidString) → \(chars.count) chars: \(summary)",
                         category: .discover, peripheral: self.peripheralIDString)

            // Update diagnostics list.
            let entry = DiscoveredService(uuid: service.uuid, characteristicUUIDs: chars.map(\.uuid))
            if let idx = self.discoveredServices.firstIndex(where: { $0.uuid == service.uuid }) {
                self.discoveredServices[idx] = entry
            } else {
                self.discoveredServices.append(entry)
            }

            // Try to bind notify + write within this service.
            var notifyCh: CBCharacteristic?
            var writeCh: CBCharacteristic?
            for ch in chars {
                if ch.uuid == JBDProtocol.notifyCharacteristicUUID
                    || ch.properties.contains(.notify) || ch.properties.contains(.indicate) {
                    if ch.uuid == JBDProtocol.notifyCharacteristicUUID || notifyCh == nil {
                        notifyCh = ch
                    }
                }
                if ch.uuid == JBDProtocol.writeCharacteristicUUID
                    || ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse) {
                    if ch.uuid == JBDProtocol.writeCharacteristicUUID || writeCh == nil {
                        writeCh = ch
                    }
                }
            }

            // Only commit if this service has both — and prefer the canonical FF00.
            if let notifyCh, let writeCh, self.matchedServiceUUID == nil
                || service.uuid == JBDProtocol.serviceUUID {
                self.notifyCharacteristic = notifyCh
                self.writeCharacteristic = writeCh
                self.matchedServiceUUID = service.uuid
                peripheral.setNotifyValue(true, for: notifyCh)
                self.log.log(
                    "Bound service \(service.uuid.uuidString): notify=\(notifyCh.uuid.uuidString), write=\(writeCh.uuid.uuidString)",
                    category: .discover, peripheral: self.peripheralIDString
                )
                self.state = .ready
                self.startPolling()
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let id = peripheral.identifier.uuidString
        let cuuid = characteristic.uuid.uuidString
        if let error {
            Task { @MainActor in
                self.log.log("Notify subscribe error on \(cuuid): \(error.localizedDescription)",
                             level: .error, category: .notify, peripheral: id)
            }
        } else {
            Task { @MainActor in
                self.log.log("Notify subscribed on \(cuuid) (isNotifying=\(characteristic.isNotifying))",
                             category: .notify, peripheral: id)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let id = peripheral.identifier.uuidString
        if let error {
            Task { @MainActor in
                self.log.log("Write error: \(error.localizedDescription)",
                             level: .error, category: .write, peripheral: id)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let id = peripheral.identifier.uuidString
        let cuuid = characteristic.uuid
        let data = characteristic.value
        if let error {
            Task { @MainActor in
                self.log.log("Notify error: \(error.localizedDescription)",
                             level: .error, category: .notify, peripheral: id)
            }
            return
        }
        guard let data else { return }

        Task { @MainActor in
            self.log.log("← chunk \(data.count)B on \(cuuid.uuidString): \(data.hexLog)",
                         level: .debug, category: .notify, peripheral: id)
            // Accept notifies on the bound notify characteristic only — but if we
            // haven't bound one yet, accept any (helps debugging unfamiliar BMSes).
            let acceptable = self.notifyCharacteristic.map { $0.uuid == cuuid } ?? true
            guard acceptable else { return }
            for frame in self.assembler.append(data) {
                self.handleFrame(frame)
            }
        }
    }
}

extension CBCharacteristicProperties {
    var summary: String {
        var parts: [String] = []
        if contains(.read) { parts.append("R") }
        if contains(.write) { parts.append("W") }
        if contains(.writeWithoutResponse) { parts.append("Wn") }
        if contains(.notify) { parts.append("N") }
        if contains(.indicate) { parts.append("I") }
        return parts.joined()
    }
}
