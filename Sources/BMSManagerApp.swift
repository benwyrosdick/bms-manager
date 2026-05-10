import SwiftUI
import SwiftData

@main
struct BMSManagerApp: App {
    @StateObject private var ble = BLEManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
        }
        .modelContainer(for: [Battery.self, BatteryGroup.self])
    }
}

struct RootView: View {
    @AppStorage(AppSettings.debugToolsKey) private var debugToolsEnabled: Bool = false

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "bolt.batteryblock.fill") }

            ScannerView()
                .tabItem { Label("Scan", systemImage: "antenna.radiowaves.left.and.right") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }

            if debugToolsEnabled {
                DebugLogView()
                    .tabItem { Label("Debug", systemImage: "ladybug.fill") }
            }
        }
    }
}
