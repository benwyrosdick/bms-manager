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
                            NavigationLink {
                                GroupDetailView(group: group)
                            } label: {
                                GroupRow(group: group)
                            }
                        }
                        .onDelete(perform: deleteGroups)
                    }
                }

                if !ungrouped.isEmpty {
                    Section(groups.isEmpty ? "Batteries" : "Ungrouped") {
                        ForEach(ungrouped) { battery in
                            NavigationLink {
                                BatteryDetailView(battery: battery)
                            } label: {
                                BatteryRow(battery: battery)
                            }
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
            ble.disconnect(savedIdentifier: battery.peripheralIdentifier)
            modelContext.delete(battery)
        }
    }
}

private struct BatteryRow: View {
    @EnvironmentObject private var ble: BLEManager
    let battery: Battery

    var body: some View {
        let connection = ble.connection(for: battery.peripheralIdentifier)
        let stats = connection?.stats

        HStack(spacing: 12) {
            BatteryIcon(soc: stats?.stateOfCharge, charging: stats?.isCharging == true)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(battery.name).font(.headline)
                if let stats {
                    Text("\(Format.volts(stats.voltage)) · \(Format.amps(stats.current))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text(connectionStateLabel(connection?.state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let stats {
                Text(Format.percent(stats.stateOfCharge))
                    .font(.title3).bold().monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    private func connectionStateLabel(_ state: ConnectionState?) -> String {
        switch state {
        case .connecting: "Connecting…"
        case .discovering: "Discovering…"
        case .ready: "Connected"
        case .failed(let msg): "Error: \(msg)"
        case .disconnected, nil: "Offline"
        }
    }
}

private struct GroupRow: View {
    @EnvironmentObject private var ble: BLEManager
    let group: BatteryGroup

    private var aggregateStats: BatteryStats? {
        let collected: [BatteryStats] = group.batteries.compactMap {
            ble.connection(for: $0.peripheralIdentifier)?.stats
        }
        guard collected.count == group.batteries.count, !collected.isEmpty else { return nil }
        return collected.aggregated(as: group.configuration)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: group.configuration == .series ? "rectangle.connected.to.line.below" : "rectangle.3.group.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.headline)
                Text("\(group.configuration.displayName) · \(group.batteries.count) batteries")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let s = aggregateStats {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.percent(s.stateOfCharge)).font(.headline).monospacedDigit()
                    Text(Format.volts(s.voltage)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
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
