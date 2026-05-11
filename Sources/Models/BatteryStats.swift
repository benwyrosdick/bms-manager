import Foundation

struct BatteryStats: Equatable, Sendable {
    var voltage: Double
    var current: Double
    var stateOfCharge: Double
    var remainingCapacityAh: Double
    var nominalCapacityAh: Double
    var cycleCount: Int
    var temperaturesC: [Double]
    var chargeFETOn: Bool
    var dischargeFETOn: Bool
    var cellCount: Int
    var timestamp: Date

    var isCharging: Bool { current > 0.05 }
    var isDischarging: Bool { current < -0.05 }

    var averageTemperatureC: Double? {
        guard !temperaturesC.isEmpty else { return nil }
        return temperaturesC.reduce(0, +) / Double(temperaturesC.count)
    }

    var maxTemperatureC: Double? { temperaturesC.max() }

    var powerWatts: Double { voltage * current }

    /// Returns true if every field except `timestamp` matches `other`. Used to
    /// skip republishing identical stats on every poll cycle.
    func materiallyEquals(_ other: BatteryStats) -> Bool {
        voltage == other.voltage
            && current == other.current
            && stateOfCharge == other.stateOfCharge
            && remainingCapacityAh == other.remainingCapacityAh
            && nominalCapacityAh == other.nominalCapacityAh
            && cycleCount == other.cycleCount
            && temperaturesC == other.temperaturesC
            && chargeFETOn == other.chargeFETOn
            && dischargeFETOn == other.dischargeFETOn
            && cellCount == other.cellCount
    }

    /// Time until SOC reaches 0 (discharging) or 100 (charging), as a TimeInterval.
    var timeToEmpty: TimeInterval? {
        guard isDischarging else { return nil }
        let amps = abs(current)
        guard amps > 0 else { return nil }
        let hours = remainingCapacityAh / amps
        return hours * 3600
    }

    var timeToFull: TimeInterval? {
        guard isCharging else { return nil }
        let amps = current
        guard amps > 0 else { return nil }
        let missing = max(nominalCapacityAh - remainingCapacityAh, 0)
        let hours = missing / amps
        return hours * 3600
    }
}

extension Array where Element == BatteryStats {
    /// Aggregate the snapshot of multiple batteries into a single virtual stat
    /// using a series or parallel rule. Returns nil if the array is empty.
    func aggregated(as configuration: GroupConfiguration) -> BatteryStats? {
        guard let first = self.first, !isEmpty else { return nil }
        let count = Double(self.count)

        switch configuration {
        case .series:
            // Voltage adds, current is shared, capacity is the weakest pack.
            let voltage = self.reduce(0) { $0 + $1.voltage }
            let current = self.map(\.current).reduce(0, +) / count
            let soc = self.map(\.stateOfCharge).min() ?? first.stateOfCharge
            let remaining = self.map(\.remainingCapacityAh).min() ?? first.remainingCapacityAh
            let nominal = self.map(\.nominalCapacityAh).min() ?? first.nominalCapacityAh
            let cycles = self.map(\.cycleCount).max() ?? first.cycleCount
            return BatteryStats(
                voltage: voltage,
                current: current,
                stateOfCharge: soc,
                remainingCapacityAh: remaining,
                nominalCapacityAh: nominal,
                cycleCount: cycles,
                temperaturesC: self.flatMap(\.temperaturesC),
                chargeFETOn: self.allSatisfy(\.chargeFETOn),
                dischargeFETOn: self.allSatisfy(\.dischargeFETOn),
                cellCount: self.map(\.cellCount).reduce(0, +),
                timestamp: self.map(\.timestamp).max() ?? .now
            )

        case .parallel:
            // Voltage averages, current and capacity sum.
            let voltage = self.reduce(0) { $0 + $1.voltage } / count
            let current = self.reduce(0) { $0 + $1.current }
            let remaining = self.reduce(0) { $0 + $1.remainingCapacityAh }
            let nominal = self.reduce(0) { $0 + $1.nominalCapacityAh }
            let soc = nominal > 0 ? (remaining / nominal) * 100.0 : (self.map(\.stateOfCharge).reduce(0, +) / count)
            let cycles = self.map(\.cycleCount).max() ?? first.cycleCount
            return BatteryStats(
                voltage: voltage,
                current: current,
                stateOfCharge: soc,
                remainingCapacityAh: remaining,
                nominalCapacityAh: nominal,
                cycleCount: cycles,
                temperaturesC: self.flatMap(\.temperaturesC),
                chargeFETOn: self.allSatisfy(\.chargeFETOn),
                dischargeFETOn: self.allSatisfy(\.dischargeFETOn),
                cellCount: first.cellCount,
                timestamp: self.map(\.timestamp).max() ?? .now
            )
        }
    }
}
