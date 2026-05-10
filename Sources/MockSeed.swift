#if targetEnvironment(simulator)
import Foundation
import SwiftData

/// Populates the SwiftData store with realistic mock batteries and groups
/// when running in the iOS Simulator. Used for App Store screenshots and
/// for testing the UI without real BMS hardware.
///
/// **Never executes on a real device** — the entire file is wrapped in
/// `#if targetEnvironment(simulator)`, so it isn't even compiled into
/// device builds.
@MainActor
enum MockSeed {
    static func seedIfNeeded(modelContext: ModelContext, ble: BLEManager) {
        // Skip if the user has already added (or seeded) anything.
        let descriptor = FetchDescriptor<Battery>()
        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
            // Make sure live BatteryConnections exist for any seeded record.
            for battery in existing where ble.connection(for: battery.peripheralIdentifier) == nil {
                reseedConnection(for: battery, ble: ble)
            }
            return
        }

        // 4 LiFePO4 12V batteries + a 2-pack parallel house bank.
        let blueprints: [Blueprint] = [
            Blueprint(
                name: "Starboard House",
                soc: 76, current: -8.5,
                nominalAh: 100, cycles: 142, tempC: 22.4,
                manufacturer: "Impulse Lithium", model: "IL-12100", firmware: "2.6",
                cellOffsets: [+2, -1, 0, -1]
            ),
            Blueprint(
                name: "Port House",
                soc: 81, current: -8.5,
                nominalAh: 100, cycles: 138, tempC: 22.8,
                manufacturer: "Impulse Lithium", model: "IL-12100", firmware: "2.6",
                cellOffsets: [+1, +1, -1, -1]
            ),
            Blueprint(
                name: "Bow Thruster",
                soc: 100, current: 0.0,
                nominalAh: 100, cycles: 28, tempC: 19.1,
                manufacturer: "Impulse Lithium", model: "IL-12100", firmware: "2.6",
                cellOffsets: [0, 0, 0, 0]
            ),
            Blueprint(
                name: "Solar Bank",
                soc: 65, current: +12.3,
                nominalAh: 100, cycles: 87, tempC: 24.7,
                manufacturer: "Renogy", model: "RBT100LFP", firmware: "1.4",
                cellOffsets: [+3, -2, +1, -2]
            )
        ]

        var saved: [Battery] = []
        for (i, bp) in blueprints.enumerated() {
            let uuid = UUID()
            let battery = Battery(
                name: bp.name,
                peripheralIdentifier: uuid.uuidString,
                advertisedName: "JBD-BMS",
                nominalCapacityAh: bp.nominalAh,
                sortOrder: i
            )
            modelContext.insert(battery)
            saved.append(battery)
            ble.registerMock(makeConnection(uuid: uuid, blueprint: bp))
        }

        // A parallel house bank: Starboard + Port.
        let bank = BatteryGroup(name: "House Bank", configuration: .parallel)
        modelContext.insert(bank)
        for battery in saved.prefix(2) {
            battery.group = bank
        }

        try? modelContext.save()
    }

    /// On subsequent launches the SwiftData records are already there, so we
    /// only need to rebuild the in-memory mock connection objects to repopulate
    /// the dashboard's live readings.
    private static func reseedConnection(for battery: Battery, ble: BLEManager) {
        guard let uuid = UUID(uuidString: battery.peripheralIdentifier) else { return }
        // Look up which blueprint to use by name; fall back to a generic one.
        let bp: Blueprint = matchingBlueprint(for: battery.name) ?? Blueprint(
            name: battery.name,
            soc: 88, current: 0,
            nominalAh: battery.nominalCapacityAh ?? 100,
            cycles: 50, tempC: 22.0,
            manufacturer: "Acme BMS", model: "Generic", firmware: "1.0",
            cellOffsets: [0, 0, 0, 0]
        )
        ble.registerMock(makeConnection(uuid: uuid, blueprint: bp))
    }

    private static func matchingBlueprint(for name: String) -> Blueprint? {
        switch name {
        case "Starboard House":
            return Blueprint(name: name, soc: 76, current: -8.5,
                             nominalAh: 100, cycles: 142, tempC: 22.4,
                             manufacturer: "Impulse Lithium", model: "IL-12100", firmware: "2.6",
                             cellOffsets: [+2, -1, 0, -1])
        case "Port House":
            return Blueprint(name: name, soc: 81, current: -8.5,
                             nominalAh: 100, cycles: 138, tempC: 22.8,
                             manufacturer: "Impulse Lithium", model: "IL-12100", firmware: "2.6",
                             cellOffsets: [+1, +1, -1, -1])
        case "Bow Thruster":
            return Blueprint(name: name, soc: 100, current: 0.0,
                             nominalAh: 100, cycles: 28, tempC: 19.1,
                             manufacturer: "Impulse Lithium", model: "IL-12100", firmware: "2.6",
                             cellOffsets: [0, 0, 0, 0])
        case "Solar Bank":
            return Blueprint(name: name, soc: 65, current: +12.3,
                             nominalAh: 100, cycles: 87, tempC: 24.7,
                             manufacturer: "Renogy", model: "RBT100LFP", firmware: "1.4",
                             cellOffsets: [+3, -2, +1, -2])
        default: return nil
        }
    }

    private static func makeConnection(uuid: UUID, blueprint bp: Blueprint) -> BatteryConnection {
        let stats = makeStats(blueprint: bp)
        let cells = makeCells(blueprint: bp)
        let info = DeviceInfo(
            manufacturer: bp.manufacturer,
            modelNumber: bp.model,
            serialNumber: "SN-\(uuid.uuidString.prefix(8))",
            firmwareRevision: bp.firmware,
            hardwareRevision: "B1",
            softwareRevision: nil,
            pnpId: nil,
            bmsHardwareVersion: "JBD-SP04S001 V\(bp.firmware)"
        )
        return BatteryConnection(
            mockIdentifier: uuid,
            stats: stats,
            cellVoltages: cells,
            deviceInfo: info
        )
    }

    private static func makeStats(blueprint bp: Blueprint) -> BatteryStats {
        let packVoltage = packVoltage(forSOC: bp.soc, current: bp.current)
        let remaining = bp.nominalAh * (bp.soc / 100.0)
        return BatteryStats(
            voltage: packVoltage,
            current: bp.current,
            stateOfCharge: bp.soc,
            remainingCapacityAh: remaining,
            nominalCapacityAh: bp.nominalAh,
            cycleCount: bp.cycles,
            temperaturesC: [bp.tempC, bp.tempC - 0.5],
            chargeFETOn: true,
            dischargeFETOn: true,
            cellCount: 4,
            timestamp: .now
        )
    }

    private static func makeCells(blueprint bp: Blueprint) -> [Double] {
        let cellNominal = packVoltage(forSOC: bp.soc, current: bp.current) / 4.0
        return bp.cellOffsets.map { mvOffset in
            cellNominal + Double(mvOffset) / 1000.0
        }
    }

    /// Rough LiFePO4 4S voltage curve. Resting voltage at the given SOC, with
    /// a fudge for current (positive = charging boosts voltage, negative = sag).
    private static func packVoltage(forSOC soc: Double, current: Double) -> Double {
        let resting: Double
        switch soc {
        case ..<10: resting = 12.0
        case ..<20: resting = 12.8
        case ..<50: resting = 13.1
        case ..<80: resting = 13.25
        case ..<95: resting = 13.4
        case ..<100: resting = 13.5
        default: resting = 13.6
        }
        let loadSag = current * 0.012   // ~12mΩ pack impedance
        return resting + loadSag
    }

    private struct Blueprint {
        let name: String
        let soc: Double
        let current: Double
        let nominalAh: Double
        let cycles: Int
        let tempC: Double
        let manufacturer: String
        let model: String
        let firmware: String
        let cellOffsets: [Int]   // millivolt deltas around the per-cell average
    }
}
#endif
