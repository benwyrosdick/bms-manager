import SwiftUI
import SwiftData

struct GroupDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var ble: BLEManager
    @Bindable var group: BatteryGroup
    @State private var editing = false

    private var collectedStats: [BatteryStats] {
        group.batteries.compactMap { ble.connection(for: $0.peripheralIdentifier)?.stats }
    }

    private var aggregate: BatteryStats? {
        let stats = collectedStats
        guard stats.count == group.batteries.count, !stats.isEmpty else { return nil }
        return stats.aggregated(as: group.configuration)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let stats = aggregate {
                    SOCBar(percent: stats.stateOfCharge, height: 16).padding(.horizontal)
                    StatGrid(stats: stats).padding(.horizontal)
                } else {
                    Text("Waiting for all member batteries to connect (\(collectedStats.count)/\(group.batteries.count))…")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Members").font(.headline).padding(.horizontal)
                    ForEach(group.batteries.sorted(by: { $0.sortOrder < $1.sortOrder })) { battery in
                        NavigationLink {
                            BatteryDetailView(battery: battery)
                        } label: {
                            MemberRow(battery: battery)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            GroupEditView(group: group)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    group.configuration.displayName,
                    systemImage: group.configuration == .series
                        ? "rectangle.connected.to.line.below"
                        : "rectangle.3.group.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let stats = aggregate {
                    Text(Format.percent(stats.stateOfCharge))
                        .font(.system(size: 36, weight: .bold)).monospacedDigit()
                    Text(stats.isCharging ? "Charging" : (stats.isDischarging ? "Discharging" : "Idle"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}

private struct MemberRow: View {
    @EnvironmentObject private var ble: BLEManager
    let battery: Battery

    var body: some View {
        let stats = ble.connection(for: battery.peripheralIdentifier)?.stats
        HStack(spacing: 12) {
            BatteryIcon(soc: stats?.stateOfCharge, charging: stats?.isCharging == true)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(battery.name).font(.body)
                if let s = stats {
                    Text("\(Format.volts(s.voltage)) · \(Format.amps(s.current))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text("Offline").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let s = stats {
                Text(Format.percent(s.stateOfCharge)).font(.body).bold().monospacedDigit()
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct GroupEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Battery.sortOrder) private var allBatteries: [Battery]

    let group: BatteryGroup?

    @State private var name: String = ""
    @State private var configuration: GroupConfiguration = .parallel
    @State private var memberIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    Picker("Configuration", selection: $configuration) {
                        ForEach(GroupConfiguration.allCases) { cfg in
                            Text(cfg.displayName).tag(cfg)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Batteries") {
                    if eligibleBatteries.isEmpty {
                        Text("Add batteries from the Scan tab first.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(eligibleBatteries) { battery in
                            MultiSelectRow(
                                name: battery.name,
                                isSelected: memberIDs.contains(battery.id)
                            ) {
                                if memberIDs.contains(battery.id) {
                                    memberIDs.remove(battery.id)
                                } else {
                                    memberIDs.insert(battery.id)
                                }
                            }
                        }
                    }
                }

                if configuration == .series {
                    Section {
                        Text("In a series group, individual battery voltages are summed and the lowest SOC dictates the group SOC.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text("In a parallel group, capacities and currents are summed and voltages are averaged.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(group == nil ? "New group" : "Edit group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var eligibleBatteries: [Battery] {
        allBatteries.filter { $0.group == nil || $0.group?.id == group?.id }
    }

    private func load() {
        if let group {
            name = group.name
            configuration = group.configuration
            memberIDs = Set(group.batteries.map(\.id))
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let target: BatteryGroup
        if let group {
            group.name = cleanName
            group.configuration = configuration
            target = group
        } else {
            target = BatteryGroup(name: cleanName, configuration: configuration)
            modelContext.insert(target)
        }

        // Update membership.
        for battery in allBatteries {
            if memberIDs.contains(battery.id) {
                battery.group = target
            } else if battery.group?.id == target.id {
                battery.group = nil
            }
        }
        dismiss()
    }
}

private struct MultiSelectRow: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                } else {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                }
            }
        }
    }
}
