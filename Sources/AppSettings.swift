import Foundation

/// Central location for every user-tweakable preference: persistence keys,
/// canonical default values, and typed accessors for non-View call sites.
///
/// SwiftUI views bind to the keys with `@AppStorage` and use the matching
/// `…Default` constant as the initializer. Non-View code (`BatteryConnection`,
/// `Format.temp`, etc.) calls the typed accessors so the read logic lives in
/// exactly one place.
enum AppSettings {
    // MARK: Keys

    static let debugToolsKey = "debug_tools_enabled"
    static let temperatureUnitKey = "temperature_unit"
    static let pollIntervalKey = "poll_interval_seconds"
    static let cellPollingKey = "cell_polling_enabled"

    // MARK: Defaults

    static let debugToolsDefault = false
    static let temperatureUnitDefault: TemperatureUnit = .celsius
    static let pollIntervalDefault: TimeInterval = 3.0
    static let cellPollingDefault = true

    // MARK: Typed accessors (for non-View readers)

    static var pollInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: pollIntervalKey)
        return stored > 0 ? stored : pollIntervalDefault
    }

    static var cellPollingEnabled: Bool {
        UserDefaults.standard.object(forKey: cellPollingKey) as? Bool ?? cellPollingDefault
    }

    static var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: temperatureUnitKey) ?? "")
            ?? temperatureUnitDefault
    }
}
