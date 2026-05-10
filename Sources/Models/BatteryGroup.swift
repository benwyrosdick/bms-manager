import Foundation
import SwiftData

enum GroupConfiguration: String, Codable, CaseIterable, Identifiable {
    case series
    case parallel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .series: "Series"
        case .parallel: "Parallel"
        }
    }
}

@Model
final class BatteryGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    var configurationRaw: String
    var dateAdded: Date
    var sortOrder: Int

    @Relationship(deleteRule: .nullify, inverse: \Battery.group)
    var batteries: [Battery] = []

    var configuration: GroupConfiguration {
        get { GroupConfiguration(rawValue: configurationRaw) ?? .parallel }
        set { configurationRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        configuration: GroupConfiguration = .parallel,
        dateAdded: Date = .now,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.configurationRaw = configuration.rawValue
        self.dateAdded = dateAdded
        self.sortOrder = sortOrder
    }
}
