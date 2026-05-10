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

struct DeviceInfo: Equatable {
    var manufacturer: String?       // 0x2A29
    var modelNumber: String?        // 0x2A24
    var serialNumber: String?       // 0x2A25
    var firmwareRevision: String?   // 0x2A26
    var hardwareRevision: String?   // 0x2A27
    var softwareRevision: String?   // 0x2A28
    var pnpId: Data?                // 0x2A50 (raw 7-byte struct)
    var bmsHardwareVersion: String? // JBD 0x05 response

    var isEmpty: Bool {
        manufacturer == nil && modelNumber == nil && serialNumber == nil
            && firmwareRevision == nil && hardwareRevision == nil
            && softwareRevision == nil && pnpId == nil && bmsHardwareVersion == nil
    }
}

@MainActor
final class BatteryConnection: NSObject, ObservableObject, Identifiable {
    nonisolated let identifier: UUID
    nonisolated let peripheral: CBPeripheral?
    nonisolated var id: UUID { identifier }
    nonisolated var peripheralIDString: String { identifier.uuidString }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var stats: BatteryStats?
    @Published private(set) var cellVoltages: [Double] = []
    @Published private(set) var cellsUpdatedAt: Date?
    @Published private(set) var deviceInfo = DeviceInfo()
    @Published private(set) var lastError: String?
    @Published private(set) var discoveredServices: [DiscoveredService] = []
    @Published private(set) var matchedServiceUUID: CBUUID?
    @Published private(set) var lastFrameBytes: Data?
    @Published private(set) var pollEnabled: Bool = true

    private var hasFetchedHardwareInfo = false

    private weak var central: CBCentralManager?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private let assembler = JBDFrameAssembler()
    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 3.0
    private let log = BLELogger.shared

    init(peripheral: CBPeripheral, central: CBCentralManager) {
        self.identifier = peripheral.identifier
        self.peripheral = peripheral
        self.central = central
        super.init()
        peripheral.delegate = self
    }

    /// Mock init for previews and simulator screenshot seeding. Skips all
    /// CoreBluetooth wiring; callers seed `stats` etc. directly.
    init(mockIdentifier: UUID,
         stats: BatteryStats? = nil,
         cellVoltages: [Double] = [],
         deviceInfo: DeviceInfo = DeviceInfo()) {
        self.identifier = mockIdentifier
        self.peripheral = nil
        self.central = nil
        super.init()
        self.state = .ready
        self.stats = stats
        self.cellVoltages = cellVoltages
        self.cellsUpdatedAt = stats != nil ? .now : nil
        self.deviceInfo = deviceInfo
    }

    /// Update a mock connection's stats in place (e.g. to animate fake live data).
    func updateMockStats(_ stats: BatteryStats) {
        guard peripheral == nil else { return }
        self.stats = stats
    }

    // MARK: - Public controls

    func connect() {
        guard let central, let peripheral else { return }
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
        if let central, let peripheral {
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
        guard let peripheral, let writeCharacteristic else {
            log.log("Cannot write: no write characteristic", level: .warn, category: .write, peripheral: peripheralIDString)
            return
        }
        let type = writeType(for: writeCharacteristic)
        log.log("→ cell voltages cmd: \(JBDProtocol.cellVoltagesCommand.hexLog)", category: .write, peripheral: peripheralIDString)
        peripheral.writeValue(JBDProtocol.cellVoltagesCommand, for: writeCharacteristic, type: type)
    }

    // MARK: - Central callbacks

    func handleConnected() {
        guard let peripheral else { return }
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
        hasFetchedHardwareInfo = false
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
        if !hasFetchedHardwareInfo {
            hasFetchedHardwareInfo = true
            requestHardwareInfo()
        }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.requestBasicInfo()
                // Stagger the cell-voltages request so the two writes don't
                // collide in the BMS's small input buffer.
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                self.requestCellVoltages()
                try? await Task.sleep(nanoseconds: UInt64((self.pollInterval - 0.4) * 1_000_000_000))
            }
        }
    }

    private func requestCellVoltages() {
        guard let peripheral, let writeCharacteristic else { return }
        let type = writeType(for: writeCharacteristic)
        log.log("→ cell voltages cmd: \(JBDProtocol.cellVoltagesCommand.hexLog)",
                level: .debug, category: .write, peripheral: peripheralIDString)
        peripheral.writeValue(JBDProtocol.cellVoltagesCommand, for: writeCharacteristic, type: type)
    }

    /// Maps a value-update on a Device Information Service characteristic to
    /// the right `deviceInfo` field. Returns true if the UUID was recognized.
    private func applyDeviceInfoUpdate(uuid: CBUUID, data: Data) -> Bool {
        let str = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        switch uuid.uuidString.uppercased() {
        case "2A29": deviceInfo.manufacturer = str
        case "2A24": deviceInfo.modelNumber = str
        case "2A25": deviceInfo.serialNumber = str
        case "2A26": deviceInfo.firmwareRevision = str
        case "2A27": deviceInfo.hardwareRevision = str
        case "2A28": deviceInfo.softwareRevision = str
        case "2A50": deviceInfo.pnpId = data
        default: return false
        }
        log.log("DIS \(uuid.uuidString): \(str ?? data.hexLog)",
                category: .frame, peripheral: peripheralIDString)
        return true
    }

    private func requestHardwareInfo() {
        guard let peripheral, let writeCharacteristic else { return }
        let type = writeType(for: writeCharacteristic)
        log.log("→ hardware info cmd: \(JBDProtocol.hardwareInfoCommand.hexLog)",
                level: .debug, category: .write, peripheral: peripheralIDString)
        peripheral.writeValue(JBDProtocol.hardwareInfoCommand, for: writeCharacteristic, type: type)
    }

    private func requestBasicInfo() {
        guard let peripheral, let writeCharacteristic else {
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
                let cells = try JBDProtocol.decodeCellVoltages(payload: payload)
                cellVoltages = cells
                cellsUpdatedAt = .now
                let mn = cells.min() ?? 0
                let mx = cells.max() ?? 0
                log.log(String(format: "Cells: %d × avg=%.3fV min=%.3fV max=%.3fV Δ=%.3fV",
                               cells.count, cells.reduce(0, +) / Double(max(cells.count, 1)),
                               mn, mx, mx - mn),
                        category: .frame, peripheral: peripheralIDString)
            case 0x05:
                let str = String(data: payload, encoding: .ascii)?
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
                if let str, !str.isEmpty {
                    deviceInfo.bmsHardwareVersion = str
                    log.log("BMS hardware: \(str)", category: .frame, peripheral: peripheralIDString)
                }
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

            // If this is the standard Device Information Service, read each
            // readable characteristic so we can populate manufacturer / model /
            // firmware fields without prompting the user.
            if service.uuid == CBUUID(string: "180A") {
                for ch in chars where ch.properties.contains(.read) {
                    peripheral.readValue(for: ch)
                }
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
                self.log.log(
                    "Bound service \(service.uuid.uuidString): notify=\(notifyCh.uuid.uuidString), write=\(writeCh.uuid.uuidString)",
                    category: .discover, peripheral: self.peripheralIDString
                )
                // Subscribe to notifications. We deliberately DO NOT mark .ready
                // or start polling yet — wait for didUpdateNotificationStateFor
                // to confirm isNotifying=true, otherwise the BMS firmware may
                // process our read command before it has acknowledged the CCCD
                // write, and the response notify is dropped on the floor.
                peripheral.setNotifyValue(true, for: notifyCh)
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
        let isNotifying = characteristic.isNotifying
        if let error {
            Task { @MainActor in
                self.log.log("Notify subscribe error on \(cuuid): \(error.localizedDescription)",
                             level: .error, category: .notify, peripheral: id)
                self.state = .failed(error.localizedDescription)
            }
            return
        }
        Task { @MainActor in
            self.log.log("Notify subscribed on \(cuuid) (isNotifying=\(isNotifying))",
                         category: .notify, peripheral: id)
            // Only flip to ready and start polling once the CCCD write has
            // been acknowledged by the peripheral.
            guard isNotifying,
                  self.notifyCharacteristic?.uuid == characteristic.uuid else { return }
            self.state = .ready
            // Brief grace period — some BMS firmwares need a moment after
            // ACKing the CCCD before they're ready to answer a read.
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.startPolling()
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

            // Route Device Information Service reads into the deviceInfo struct.
            if self.applyDeviceInfoUpdate(uuid: cuuid, data: data) {
                return
            }

            // Otherwise treat as a JBD notify chunk on the bound notify char
            // (or any char, if we haven't bound one yet — helpful for debugging).
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
