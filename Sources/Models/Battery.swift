import Foundation
import SwiftData

@Model
final class Battery {
    @Attribute(.unique) var id: UUID
    var name: String
    var peripheralIdentifier: String
    var advertisedName: String?
    var nominalCapacityAh: Double?
    var dateAdded: Date
    var sortOrder: Int

    var group: BatteryGroup?

    init(
        id: UUID = UUID(),
        name: String,
        peripheralIdentifier: String,
        advertisedName: String? = nil,
        nominalCapacityAh: Double? = nil,
        dateAdded: Date = .now,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.peripheralIdentifier = peripheralIdentifier
        self.advertisedName = advertisedName
        self.nominalCapacityAh = nominalCapacityAh
        self.dateAdded = dateAdded
        self.sortOrder = sortOrder
    }
}
