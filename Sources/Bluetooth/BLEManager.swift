import Foundation
import CoreBluetooth
import Combine

struct DiscoveredPeripheral: Identifiable, Equatable {
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var advertisedServices: [CBUUID]
    var lastSeen: Date

    var id: UUID { peripheral.identifier }
}

@MainActor
final class BLEManager: NSObject, ObservableObject {
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var discovered: [DiscoveredPeripheral] = []
    @Published private(set) var connections: [UUID: BatteryConnection] = [:]

    private var central: CBCentralManager!
    private let staleInterval: TimeInterval = 15
    private var connectionObservers: [UUID: AnyCancellable] = [:]
    private let log = BLELogger.shared
    // lastSeen is tracked off-band so it doesn't republish `discovered` on every
    // advertising packet. pruneStale reads it on a 1Hz timer.
    private var lastSeenByPeripheral: [UUID: Date] = [:]
    private var pruneTask: Task<Void, Never>?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionShowPowerAlertKey: true
        ])
    }

    // MARK: - Scanning

    func startScan() {
        guard bluetoothState == .poweredOn else {
            log.log("Cannot scan: bluetooth state \(bluetoothState.rawValue)", level: .warn, category: .scan)
            return
        }
        discovered.removeAll()
        lastSeenByPeripheral.removeAll()
        // Many BMS modules don't include FF00 in their advertisement, so scan
        // unfiltered and apply name/UUID heuristics in didDiscover.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        startPruneLoop()
        log.log("Scan started", category: .scan)
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
        pruneTask?.cancel()
        pruneTask = nil
        log.log("Scan stopped", category: .scan)
    }

    private func startPruneLoop() {
        pruneTask?.cancel()
        pruneTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.pruneStale()
            }
        }
    }

    // MARK: - Connections

    /// Pure lookup. Safe to call from a SwiftUI view body — does not mutate state.
    func connection(for peripheralIdentifier: String) -> BatteryConnection? {
        guard let uuid = UUID(uuidString: peripheralIdentifier) else { return nil }
        return connections[uuid]
    }

    /// Ensures a BatteryConnection exists for the given saved peripheral, registering
    /// one via CoreBluetooth's known-peripheral cache if needed. Call from `.onAppear`,
    /// `.task`, or button handlers — not from view body.
    @discardableResult
    func prepareConnection(for peripheralIdentifier: String) -> BatteryConnection? {
        guard let uuid = UUID(uuidString: peripheralIdentifier) else { return nil }
        if let existing = connections[uuid] { return existing }
        let known = central.retrievePeripherals(withIdentifiers: [uuid])
        guard let peripheral = known.first else {
            log.log("No cached peripheral for \(uuid.uuidString.prefix(8))…; scan first",
                    level: .warn, category: .connect, peripheral: uuid.uuidString)
            return nil
        }
        return register(peripheral: peripheral)
    }

    /// Register a freshly-discovered peripheral.
    @discardableResult
    func registerDiscovered(_ peripheral: CBPeripheral) -> BatteryConnection {
        if let existing = connections[peripheral.identifier] { return existing }
        return register(peripheral: peripheral)
    }

    @discardableResult
    private func register(peripheral: CBPeripheral) -> BatteryConnection {
        let conn = BatteryConnection(peripheral: peripheral, central: central)
        connections[peripheral.identifier] = conn
        connectionObservers[peripheral.identifier] = conn.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.objectWillChange.send() }
            }
        log.log("Registered peripheral", category: .connect, peripheral: peripheral.identifier.uuidString)
        return conn
    }

    func openAndConnect(peripheral: CBPeripheral) {
        registerDiscovered(peripheral).connect()
    }

    /// Insert a pre-built mock connection (no CoreBluetooth involvement).
    /// Used only by `MockSeed` on the simulator for screenshot data.
    func registerMock(_ connection: BatteryConnection) {
        connections[connection.id] = connection
        connectionObservers[connection.id] = connection.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.objectWillChange.send() }
            }
    }

    func openAndConnect(savedIdentifier: String) {
        prepareConnection(for: savedIdentifier)?.connect()
    }

    /// If a connection already exists, ask it to reconnect (fast path that
    /// reuses the CBPeripheral). Otherwise prepare + connect from scratch.
    func reconnectOrOpen(savedIdentifier: String) {
        if let connection = connection(for: savedIdentifier) {
            connection.reconnect()
        } else {
            openAndConnect(savedIdentifier: savedIdentifier)
        }
    }

    func disconnect(savedIdentifier: String) {
        guard let uuid = UUID(uuidString: savedIdentifier) else { return }
        connections[uuid]?.disconnect()
    }

    /// Tear down the connection for a saved battery being removed: cancels the
    /// active link and drops the in-memory `BatteryConnection` and its observer
    /// so the `CBPeripheral` is released.
    func forgetConnection(savedIdentifier: String) {
        guard let uuid = UUID(uuidString: savedIdentifier) else { return }
        connections[uuid]?.disconnect()
        connections.removeValue(forKey: uuid)
        connectionObservers.removeValue(forKey: uuid)
    }

    // MARK: - Maintenance

    private func upsertDiscovery(
        peripheral: CBPeripheral,
        name: String,
        rssi: Int,
        services: [CBUUID]
    ) {
        // Always refresh staleness (off-band, no @Published churn).
        lastSeenByPeripheral[peripheral.identifier] = .now

        if let idx = discovered.firstIndex(where: { $0.id == peripheral.identifier }) {
            // Only republish the array if user-visible fields changed. RSSI is
            // bucketed to ±5 dBm to absorb the per-packet noise that makes the
            // shown value jitter on every advertising tick.
            let existing = discovered[idx]
            let bucketedNew = (rssi / 5) * 5
            let bucketedOld = (existing.rssi / 5) * 5
            let materialChange =
                existing.name != name
                || bucketedNew != bucketedOld
                || existing.advertisedServices != services
            if materialChange {
                discovered[idx] = DiscoveredPeripheral(
                    peripheral: peripheral,
                    name: name,
                    rssi: rssi,
                    advertisedServices: services,
                    lastSeen: .now
                )
            }
        } else {
            // Insert in name-sorted order so the view can iterate `discovered`
            // directly without re-sorting on every render.
            let entry = DiscoveredPeripheral(
                peripheral: peripheral,
                name: name,
                rssi: rssi,
                advertisedServices: services,
                lastSeen: .now
            )
            let insertIdx = discovered.firstIndex(where: { sortsAfter(entry, $0) }) ?? discovered.endIndex
            discovered.insert(entry, at: insertIdx)
            log.log(
                "Discovered \(name) RSSI \(rssi) services=[\(services.map(\.uuidString).joined(separator: ","))]",
                category: .scan,
                peripheral: peripheral.identifier.uuidString
            )
        }
    }

    /// Stable name-then-UUID ordering. Returns true if `a` should be placed
    /// before `b`.
    private func sortsAfter(_ a: DiscoveredPeripheral, _ b: DiscoveredPeripheral) -> Bool {
        let cmp = a.name.localizedCaseInsensitiveCompare(b.name)
        if cmp != .orderedSame { return cmp == .orderedAscending }
        return a.id.uuidString < b.id.uuidString
    }

    private func pruneStale() {
        let cutoff = Date().addingTimeInterval(-staleInterval)
        // Find stale IDs first, then only mutate `discovered` if there's
        // anything to remove — avoids a no-op `removeAll` that would still
        // republish the array.
        let stale = lastSeenByPeripheral.compactMap { $0.value < cutoff ? $0.key : nil }
        guard !stale.isEmpty else { return }
        for id in stale { lastSeenByPeripheral.removeValue(forKey: id) }
        let staleSet = Set(stale)
        if discovered.contains(where: { staleSet.contains($0.id) }) {
            discovered.removeAll { staleSet.contains($0.id) }
        }
    }
}

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor in
            self.bluetoothState = state
            self.log.log("Central state \(state.description)", category: .scan)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? "Unknown"
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let looksLikeBMS = serviceUUIDs.contains(JBDProtocol.serviceUUID)
            || name.range(of: "bms", options: .caseInsensitive) != nil
            || name.range(of: "battery", options: .caseInsensitive) != nil
            || name.range(of: "lifepo", options: .caseInsensitive) != nil
            || name.range(of: "impulse", options: .caseInsensitive) != nil
        guard looksLikeBMS else { return }

        Task { @MainActor in
            self.upsertDiscovery(
                peripheral: peripheral,
                name: name,
                rssi: RSSI.intValue,
                services: serviceUUIDs
            )
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier.uuidString
        Task { @MainActor in
            self.log.log("Connected", category: .connect, peripheral: id)
            self.connections[peripheral.identifier]?.handleConnected()
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let id = peripheral.identifier.uuidString
        let msg = error?.localizedDescription ?? "unknown"
        Task { @MainActor in
            self.log.log("Connect failed: \(msg)", level: .error, category: .connect, peripheral: id)
            self.connections[peripheral.identifier]?.handleDisconnected(error: error)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let id = peripheral.identifier.uuidString
        let msg = error?.localizedDescription
        Task { @MainActor in
            if let msg {
                self.log.log("Disconnected: \(msg)", level: .warn, category: .connect, peripheral: id)
            } else {
                self.log.log("Disconnected", category: .connect, peripheral: id)
            }
            self.connections[peripheral.identifier]?.handleDisconnected(error: error)
        }
    }
}

extension CBManagerState {
    var description: String {
        switch self {
        case .unknown: "unknown"
        case .resetting: "resetting"
        case .unsupported: "unsupported"
        case .unauthorized: "unauthorized"
        case .poweredOff: "poweredOff"
        case .poweredOn: "poweredOn"
        @unknown default: "?"
        }
    }
}
