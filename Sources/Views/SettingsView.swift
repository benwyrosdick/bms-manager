import SwiftUI

/// Discrete poll intervals offered in Settings. Anything between 1 and 30 s
/// would also work; these are the buckets that read sanely as user choices.
private let pollIntervalOptions: [Double] = [1, 3, 5, 10, 30]

struct SettingsView: View {
    @AppStorage(AppSettings.debugToolsKey) private var debugToolsEnabled: Bool = AppSettings.debugToolsDefault
    @AppStorage(AppSettings.temperatureUnitKey) private var temperatureUnitRaw: String = AppSettings.temperatureUnitDefault.rawValue
    @AppStorage(AppSettings.pollIntervalKey) private var pollInterval: Double = AppSettings.pollIntervalDefault
    @AppStorage(AppSettings.cellPollingKey) private var cellPollingEnabled: Bool = AppSettings.cellPollingDefault

    private var temperatureUnit: Binding<TemperatureUnit> {
        Binding(
            get: { TemperatureUnit(rawValue: temperatureUnitRaw) ?? AppSettings.temperatureUnitDefault },
            set: { temperatureUnitRaw = $0.rawValue }
        )
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Picker("Temperature", selection: temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                }
                .themedListRows()

                Section {
                    Picker("Poll every", selection: $pollInterval) {
                        ForEach(pollIntervalOptions, id: \.self) { seconds in
                            Text(secondsLabel(seconds)).tag(seconds)
                        }
                    }

                    Toggle(isOn: $cellPollingEnabled) {
                        Label("Read cell voltages", systemImage: "square.grid.3x1.below.line.grid.1x2")
                    }
                } header: {
                    Text("Polling")
                } footer: {
                    Text("Lower intervals show fresher readings but use more phone battery and more BLE bandwidth. Turning off cell voltages roughly halves Bluetooth traffic per battery.")
                }
                .themedListRows()

                Section {
                    Toggle(isOn: $debugToolsEnabled) {
                        Label("Show debug tools", systemImage: "ladybug.fill")
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Adds a Debug tab with the BLE event log and frame inspector. Useful when troubleshooting a BMS that isn't responding.")
                }
                .themedListRows()

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .themedListRows()
            }
            .themedScrollBackground()
            .themedNavigation()
            .navigationTitle("Settings")
        }
    }

    private func secondsLabel(_ s: Double) -> String {
        Int(s) == 1 ? "1 second" : "\(Int(s)) seconds"
    }
}
