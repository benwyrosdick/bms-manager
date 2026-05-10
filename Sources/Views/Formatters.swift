import Foundation

enum Format {
    static func volts(_ v: Double) -> String { String(format: "%.2f V", v) }
    static func amps(_ a: Double) -> String { String(format: "%+.2f A", a) }
    static func watts(_ w: Double) -> String { String(format: "%+.0f W", w) }
    static func percent(_ p: Double) -> String { String(format: "%.0f%%", p) }
    static func tempC(_ t: Double) -> String { String(format: "%.1f °C", t) }
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
