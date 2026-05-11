import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var ble: BLEManager
    @Query(sort: \BatteryGroup.sortOrder) private var groups: [BatteryGroup]
    @Query(sort: \Battery.sortOrder) private var batteries: [Battery]

    @State private var showingNewGroup = false

    private var ungrouped: [Battery] {
        batteries.filter { $0.group == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                if groups.isEmpty && batteries.isEmpty {
                    ContentUnavailableView(
                        "No batteries yet",
                        systemImage: "bolt.batteryblock",
                        description: Text("Tap the **Scan** tab to find your BMS.")
                    )
                    .listRowBackground(Color.clear)
                }

                if !groups.isEmpty {
                    Section("Groups") {
                        ForEach(groups) { group in
                            GroupRowLink(group: group)
                        }
                        .onDelete(perform: deleteGroups)
                    }
                }

                if !ungrouped.isEmpty {
                    Section(groups.isEmpty ? "Batteries" : "Ungrouped") {
                        ForEach(ungrouped) { battery in
                            BatteryRowLink(battery: battery)
                        }
                        .onDelete { offsets in deleteBatteries(offsets, in: ungrouped) }
                    }
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingNewGroup = true
                        } label: {
                            Label("New group", systemImage: "rectangle.stack.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showingNewGroup) {
                GroupEditView(group: nil)
            }
            .onAppear { connectAllSaved() }
        }
    }

    private func connectAllSaved() {
        for battery in batteries {
            let conn = ble.prepareConnection(for: battery.peripheralIdentifier)
            if let conn, conn.state == .disconnected {
                conn.connect()
            }
        }
    }

    private func deleteGroups(_ offsets: IndexSet) {
        for offset in offsets {
            modelContext.delete(groups[offset])
        }
    }

    private func deleteBatteries(_ offsets: IndexSet, in source: [Battery]) {
        for offset in offsets {
            let battery = source[offset]
            ble.forgetConnection(savedIdentifier: battery.peripheralIdentifier)
            modelContext.delete(battery)
        }
    }
}

/// Tap-to-retry wrapper: NavigationLink when healthy, Button-that-reconnects when failed.
private struct BatteryRowLink: View {
    @EnvironmentObject private var ble: BLEManager
    let battery: Battery

    var body: some View {
        let connection = ble.connection(for: battery.peripheralIdentifier)
        if connection?.state.isFailed == true {
            Button {
                ble.reconnectOrOpen(savedIdentifier: battery.peripheralIdentifier)
            } label: {
                BatteryRow(battery: battery)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                BatteryDetailView(battery: battery)
            } label: {
                BatteryRow(battery: battery)
            }
        }
    }
}

private struct BatteryRow: View {
    @EnvironmentObject private var ble: BLEManager
    let battery: Battery

    var body: some View {
        let connection = ble.connection(for: battery.peripheralIdentifier)
        let stats = connection?.stats
        let failed = connection?.state.isFailed == true

        HStack(spacing: 12) {
            if failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                    .frame(width: 28)
            } else {
                BatteryIcon(soc: stats?.stateOfCharge, charging: stats?.isCharging == true)
                    .frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(battery.name).font(.headline)
                if failed {
                    Text("Tap to retry")
                        .font(.caption).foregroundStyle(.red)
                } else if let stats {
                    Text("\(Format.volts(stats.voltage)) · \(Format.amps(stats.current))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text(connection?.state.displayLabel ?? "Offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if failed {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
            } else if let stats {
                Text(Format.percent(stats.stateOfCharge))
                    .font(.title3).bold().monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct GroupRowLink: View {
    @EnvironmentObject private var ble: BLEManager
    let group: BatteryGroup

    var body: some View {
        let failed = group.batteries.filter {
            ble.connection(for: $0.peripheralIdentifier)?.state.isFailed == true
        }
        if !failed.isEmpty {
            Button {
                for battery in failed {
                    ble.reconnectOrOpen(savedIdentifier: battery.peripheralIdentifier)
                }
            } label: {
                GroupRow(group: group, failedCount: failed.count)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                GroupDetailView(group: group)
            } label: {
                GroupRow(group: group, failedCount: 0)
            }
        }
    }
}

private struct GroupRow: View {
    @EnvironmentObject private var ble: BLEManager
    let group: BatteryGroup
    let failedCount: Int

    private var aggregateStats: BatteryStats? {
        let collected: [BatteryStats] = group.batteries.compactMap {
            ble.connection(for: $0.peripheralIdentifier)?.stats
        }
        guard collected.count == group.batteries.count, !collected.isEmpty else { return nil }
        return collected.aggregated(as: group.configuration)
    }

    var body: some View {
        HStack(spacing: 12) {
            if failedCount > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                    .frame(width: 28)
            } else {
                Image(systemName: group.configuration.symbolName)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.headline)
                if failedCount > 0 {
                    Text("\(failedCount) of \(group.batteries.count) failed · tap to retry")
                        .font(.caption).foregroundStyle(.red)
                } else {
                    Text("\(group.configuration.displayName) · \(group.batteries.count) batteries")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if failedCount > 0 {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
            } else if let s = aggregateStats {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.percent(s.stateOfCharge)).font(.headline).monospacedDigit()
                    Text(Format.volts(s.voltage)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct BatteryIcon: View {
    let soc: Double?
    let charging: Bool

    private var iconName: String {
        if charging { return "battery.100.bolt" }
        switch soc ?? -1 {
        case ..<0: return "battery.0"
        case ..<15: return "battery.0"
        case ..<40: return "battery.25"
        case ..<65: return "battery.50"
        case ..<90: return "battery.75"
        default: return "battery.100"
        }
    }

    private var color: Color {
        guard let soc else { return .secondary }
        if charging { return .green }
        switch soc {
        case ..<20: return .red
        case ..<50: return .orange
        default: return .green
        }
    }

    var body: some View {
        Image(systemName: iconName)
            .font(.title2)
            .foregroundStyle(color)
    }
}
