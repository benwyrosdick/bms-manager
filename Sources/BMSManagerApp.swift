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
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "bolt.batteryblock.fill") }

            ScannerView()
                .tabItem { Label("Scan", systemImage: "antenna.radiowaves.left.and.right") }

            DebugLogView()
                .tabItem { Label("Debug", systemImage: "ladybug.fill") }
        }
    }
}
