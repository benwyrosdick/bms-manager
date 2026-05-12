import SwiftUI
import SwiftData

struct BatteryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var ble: BLEManager
    @Bindable var battery: Battery
    @Query(sort: \BatteryGroup.name) private var groups: [BatteryGroup]

    @State private var editingName = false
    @State private var showDiagnostics = false
    @AppStorage(AppSettings.cellPollingKey) private var cellPollingEnabled: Bool = true

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

                    if cellPollingEnabled, let connection, !connection.cellVoltages.isEmpty {
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

                if let info = connection?.deviceInfo, !info.isEmpty {
                    DeviceInfoSection(info: info)
                        .padding(.horizontal)
                }

                DisclosureGroup("Diagnostics", isExpanded: $showDiagnostics) {
                    diagnosticsContent
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Theme.background.ignoresSafeArea())
        .themedNavigation()
        .navigationTitle(battery.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editingName = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    if connection?.state == .ready || connection?.state == .connecting {
                        Button {
                            ble.disconnect(savedIdentifier: battery.peripheralIdentifier)
                        } label: {
                            Label("Disconnect", systemImage: "wifi.slash")
                        }
                    } else {
                        Button {
                            ble.openAndConnect(savedIdentifier: battery.peripheralIdentifier)
                        } label: {
                            Label("Connect", systemImage: "wifi")
                        }
                    }
                    Button {
                        connection?.reconnect()
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }

                    Divider()

                    if let connection {
                        Button {
                            connection.sendBasicInfoNow()
                        } label: {
                            Label("Refresh basic info", systemImage: "info.circle")
                        }
                        Button {
                            connection.sendCellVoltagesNow()
                        } label: {
                            Label("Refresh cells", systemImage: "square.grid.3x1.below.line.grid.1x2")
                        }
                        Button {
                            connection.setPolling(!connection.pollEnabled)
                        } label: {
                            Label(
                                connection.pollEnabled ? "Pause auto-poll" : "Resume auto-poll",
                                systemImage: connection.pollEnabled ? "pause.circle" : "play.circle"
                            )
                        }
                        Divider()
                    }

                    Button(role: .destructive) {
                        ble.forgetConnection(savedIdentifier: battery.peripheralIdentifier)
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
        connection?.state.displayLabel ?? "Offline"
    }

    private var statusPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView().controlSize(.small)
            Text(stateLabel).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
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
        .cardStyle()
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

private struct DeviceInfoSection: View {
    let info: DeviceInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device").font(.headline)
            VStack(spacing: 0) {
                row("Manufacturer", info.manufacturer)
                row("Model", info.modelNumber)
                row("Serial", info.serialNumber)
                row("Firmware", info.firmwareRevision)
                row("Hardware", info.hardwareRevision)
                row("Software", info.softwareRevision)
                row("BMS module", info.bmsHardwareVersion)
                if let pnp = info.pnpId {
                    row("PnP ID", pnp.hexLog)
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Text(value)
                    .font(.callout).fontWeight(.medium)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.vertical, 4)
        }
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
    @AppStorage(AppSettings.temperatureUnitKey) private var temperatureUnitRaw: String = AppSettings.temperatureUnitDefault.rawValue

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? AppSettings.temperatureUnitDefault
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Temperature sensors").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(temps.enumerated()), id: \.offset) { idx, t in
                    VStack {
                        Text("T\(idx + 1)").font(.caption2).foregroundStyle(.secondary)
                        Text(Format.temp(t, in: temperatureUnit)).font(.callout).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}
