import SwiftUI

enum AppSettings {
    static let debugToolsKey = "debug_tools_enabled"
}

struct SettingsView: View {
    @AppStorage(AppSettings.debugToolsKey) private var debugToolsEnabled: Bool = false

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $debugToolsEnabled) {
                        Label("Show debug tools", systemImage: "ladybug.fill")
                    }
                    .listRowBackground(Theme.surface)
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Adds a Debug tab with the BLE event log and frame inspector. Useful when troubleshooting a BMS that isn't responding.")
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .themedScrollBackground()
            .themedNavigation()
            .navigationTitle("Settings")
        }
    }
}
