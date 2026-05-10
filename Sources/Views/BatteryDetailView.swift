import SwiftUI
import SwiftData

struct BatteryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var ble: BLEManager
    @Bindable var battery: Battery
    @Query(sort: \BatteryGroup.name) private var groups: [BatteryGroup]

    @State private var editingName = false
    @State private var showDiagnostics = false

    private var connection: BatteryConnection? {
        ble.connection(for: battery.peripheralIdentifier)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let stats = connection?.stats {
                    SOCBar(percent: stats.stateOfCharge, height: 16)
                        .padding(.horizontal)

                    StatGrid(stats: stats)
                        .padding(.horizontal)

                    if !stats.temperaturesC.isEmpty {
                        TempStrip(temps: stats.temperaturesC)
                            .padding(.horizontal)
                    }

                    if let connection, !connection.cellVoltages.isEmpty {
                        CellGridView(cells: connection.cellVoltages, updatedAt: connection.cellsUpdatedAt)
                            .padding(.horizontal)
                    }

                    Text("Updated \(stats.timestamp.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                } else {
                    statusPlaceholder
                        .padding(.horizontal)
                }

                groupSection
                    .padding(.horizontal)

                manualCommandsSection
                    .padding(.horizontal)

                DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                    diagnosticsContent
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(battery.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Rename") { editingName = true }
                    if connection?.state == .ready || connection?.state == .connecting {
                        Button("Disconnect") {
                            ble.disconnect(savedIdentifier: battery.peripheralIdentifier)
                        }
                    } else {
                        Button("Connect") {
                            ble.openAndConnect(savedIdentifier: battery.peripheralIdentifier)
                        }
                    }
                    Button("Reconnect") {
                        connection?.reconnect()
                    }
                    Divider()
                    Button(role: .destructive) {
                        ble.disconnect(savedIdentifier: battery.peripheralIdentifier)
                        modelContext.delete(battery)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename battery", isPresented: $editingName) {
            TextField("Name", text: $battery.name)
            Button("Save") {}
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            let conn = ble.prepareConnection(for: battery.peripheralIdentifier)
            if conn?.state == .disconnected || conn == nil {
                ble.openAndConnect(savedIdentifier: battery.peripheralIdentifier)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            BatteryIcon(
                soc: connection?.stats?.stateOfCharge,
                charging: connection?.stats?.isCharging == true
            )
            .font(.system(size: 40))
            .frame(width: 56)

            VStack(alignment: .leading, spacing: 2) {
                if let stats = connection?.stats {
                    Text(Format.percent(stats.stateOfCharge))
                        .font(.system(size: 36, weight: .bold)).monospacedDigit()
                    Text(stats.isCharging ? "Charging" : (stats.isDischarging ? "Discharging" : "Idle"))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("—%").font(.system(size: 36, weight: .bold))
                    Text(stateLabel).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private var stateLabel: String {
        switch connection?.state {
        case .connecting: "Connecting…"
        case .discovering: "Discovering…"
        case .ready: "Connected"
        case .failed(let msg): "Error: \(msg)"
        case .disconnected, nil: "Offline"
        }
    }

    private var statusPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView().controlSize(.small)
            Text(stateLabel).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Group").font(.headline)
            Picker("Group", selection: Binding(
                get: { battery.group?.id },
                set: { newID in
                    battery.group = groups.first(where: { $0.id == newID })
                }
            )) {
                Text("None").tag(UUID?.none)
                ForEach(groups) { group in
                    Text(group.name).tag(Optional(group.id))
                }
            }
            .pickerStyle(.menu)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var manualCommandsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual commands").font(.headline)
            HStack(spacing: 12) {
                Button {
                    connection?.sendBasicInfoNow()
                } label: {
                    Label("Basic info", systemImage: "info.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    connection?.sendCellVoltagesNow()
                } label: {
                    Label("Cells", systemImage: "square.grid.3x1.below.line.grid.1x2")
                }
                .buttonStyle(.bordered)

                Button {
                    connection?.reconnect()
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            if let connection {
                Toggle("Auto-poll every 3s", isOn: Binding(
                    get: { connection.pollEnabled },
                    set: { connection.setPolling($0) }
                ))
                .font(.callout)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var diagnosticsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            DiagnosticRow(label: "State", value: stateLabel)
            DiagnosticRow(label: "Identifier", value: battery.peripheralIdentifier)
            if let connection {
                DiagnosticRow(
                    label: "Bound service",
                    value: connection.matchedServiceUUID?.uuidString ?? "—"
                )
                if !connection.discoveredServices.isEmpty {
                    Text("Services seen").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    ForEach(connection.discoveredServices) { svc in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(svc.uuid.uuidString)
                                .font(.system(.caption, design: .monospaced))
                            ForEach(svc.characteristicUUIDs, id: \.uuidString) { c in
                                Text("    " + c.uuidString)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let lastFrame = connection.lastFrameBytes {
                    Text("Last frame").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    Text(lastFrame.hexLog)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let err = connection.lastError {
                    Text("Last error").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(.top, 8)
    }
}

private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Spacer()
        }
    }
}

private struct TempStrip: View {
    let temps: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Temperature sensors").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(temps.enumerated()), id: \.offset) { idx, t in
                    VStack {
                        Text("T\(idx + 1)").font(.caption2).foregroundStyle(.secondary)
                        Text(Format.tempC(t)).font(.callout).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}
