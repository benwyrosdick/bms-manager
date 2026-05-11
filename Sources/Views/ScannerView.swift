import SwiftUI
import SwiftData
import CoreBluetooth

struct ScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var ble: BLEManager
    @Query private var savedBatteries: [Battery]

    private var savedIdentifiers: Set<String> {
        Set(savedBatteries.map(\.peripheralIdentifier))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBanner

                List {
                    if ble.discovered.isEmpty {
                        Section {
                            ContentUnavailableView {
                                Label("Looking for batteries", systemImage: "antenna.radiowaves.left.and.right")
                            } description: {
                                Text("Make sure your BMS is powered on and within range. Most BMS chips advertise as \"BMS\", \"LiFePO4\", or with the FF00 service.")
                            }
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        Section("Nearby") {
                            ForEach(ble.discovered) { entry in
                                ScannerRow(
                                    entry: entry,
                                    alreadySaved: savedIdentifiers.contains(entry.peripheral.identifier.uuidString),
                                    onAdd: { add(entry) }
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if ble.isScanning {
                        Button("Stop") { ble.stopScan() }
                    } else {
                        Button("Scan") { ble.startScan() }
                            .disabled(ble.bluetoothState != .poweredOn)
                    }
                }
            }
            .onAppear {
                if ble.bluetoothState == .poweredOn { ble.startScan() }
            }
            .onDisappear { ble.stopScan() }
            .onChange(of: ble.bluetoothState) { _, new in
                if new == .poweredOn { ble.startScan() }
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch ble.bluetoothState {
        case .poweredOn:
            EmptyView()
        case .poweredOff:
            BannerView(text: "Bluetooth is off. Enable it in Settings.", tint: .orange)
        case .unauthorized:
            BannerView(text: "BatteryScope doesn't have Bluetooth permission. Enable it in Settings.", tint: .red)
        case .unsupported:
            BannerView(text: "This device doesn't support Bluetooth LE.", tint: .red)
        case .resetting, .unknown:
            BannerView(text: "Bluetooth is initializing…", tint: .secondary)
        @unknown default:
            EmptyView()
        }
    }

    private func add(_ entry: DiscoveredPeripheral) {
        let battery = Battery(
            name: entry.name,
            peripheralIdentifier: entry.peripheral.identifier.uuidString,
            advertisedName: entry.name,
            sortOrder: savedBatteries.count
        )
        modelContext.insert(battery)
        ble.openAndConnect(peripheral: entry.peripheral)
    }
}

private struct ScannerRow: View {
    let entry: DiscoveredPeripheral
    let alreadySaved: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.headline)
                Text(entry.peripheral.identifier.uuidString)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text("\(entry.rssi) dBm").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if alreadySaved {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill").imageScale(.large)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct BannerView: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(tint.opacity(0.15))
    }
}
