import Foundation

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    var displayName: String {
        switch self {
        case .celsius: "Celsius (°C)"
        case .fahrenheit: "Fahrenheit (°F)"
        }
    }

    func convert(fromCelsius c: Double) -> Double {
        switch self {
        case .celsius: c
        case .fahrenheit: c * 9 / 5 + 32
        }
    }

    /// Resolve the user's preferred unit. Defaults to Celsius if unset.
    static var current: TemperatureUnit {
        TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: AppSettings.temperatureUnitKey) ?? "") ?? .celsius
    }
}

enum Format {
    static func volts(_ v: Double) -> String { String(format: "%.2f V", v) }
    static func amps(_ a: Double) -> String { String(format: "%+.2f A", a) }
    static func watts(_ w: Double) -> String { String(format: "%+.0f W", w) }
    static func percent(_ p: Double) -> String { String(format: "%.0f%%", p) }
    /// Formats a Celsius value in the user's preferred temperature unit.
    static func temp(_ celsius: Double) -> String {
        let unit = TemperatureUnit.current
        return String(format: "%.1f %@", unit.convert(fromCelsius: celsius), unit.symbol)
    }
    static func ah(_ ah: Double) -> String { String(format: "%.2f Ah", ah) }
    static func cycles(_ n: Int) -> String { "\(n)" }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        guard total > 0 else { return "—" }
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 {
            return String(format: "%dh %02dm", h, m)
        }
        let s = total % 60
        return String(format: "%dm %02ds", m, s)
    }
}
