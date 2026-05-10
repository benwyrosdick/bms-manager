import Foundation
import os

/// Ring-buffer log of BLE / BMS events. Observable so a SwiftUI view can show
/// it live, and mirrored to OSLog so Console.app picks it up too.
@MainActor
final class BLELogger: ObservableObject {
    static let shared = BLELogger()

    enum Level: String {
        case debug, info, warn, error

        var symbol: String {
            switch self {
            case .debug: "·"
            case .info: "→"
            case .warn: "!"
            case .error: "✗"
            }
        }
    }

    enum Category: String {
        case scan, connect, discover, write, notify, frame, app
    }

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let level: Level
        let category: Category
        let peripheral: String?
        let message: String

        var formattedTime: String {
            BLELogger.timeFormatter.string(from: date)
        }
    }

    // nonisolated lets Entry.formattedTime (a non-isolated nested struct)
    // reach this static without an actor hop. DateFormatter is Sendable in
    // current SDKs so the `(unsafe)` qualifier is no longer needed.
    nonisolated private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let osLog = Logger(subsystem: "com.benwyrosdick.battery-monitor", category: "ble")

    @Published private(set) var entries: [Entry] = []
    private let limit = 500

    private init() {}

    func log(
        _ message: String,
        level: Level = .info,
        category: Category = .app,
        peripheral: String? = nil
    ) {
        let entry = Entry(
            date: .now,
            level: level,
            category: category,
            peripheral: peripheral,
            message: message
        )
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }

        let prefix = peripheral.map { "[\($0.suffix(8))] " } ?? ""
        let line = "[\(category.rawValue)] \(prefix)\(message)"
        switch level {
        case .debug: Self.osLog.debug("\(line, privacy: .public)")
        case .info: Self.osLog.info("\(line, privacy: .public)")
        case .warn: Self.osLog.warning("\(line, privacy: .public)")
        case .error: Self.osLog.error("\(line, privacy: .public)")
        }
    }

    func clear() { entries.removeAll() }

    func dumpText() -> String {
        entries.map { entry in
            let p = entry.peripheral.map { " [\($0.suffix(8))]" } ?? ""
            return "\(entry.formattedTime) \(entry.level.symbol) [\(entry.category.rawValue)]\(p) \(entry.message)"
        }.joined(separator: "\n")
    }
}

extension Data {
    /// Hex dump suitable for logs: "DD 03 00 1B AB CD ..."
    var hexLog: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
