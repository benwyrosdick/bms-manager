import SwiftUI
import UIKit

/// Centralized palette for the BatteryScope dark theme. Uses a deep navy
/// background with slightly raised surface tones for cards, and a vivid green
/// accent that picks up the heartbeat trace from the app icon.
enum Theme {
    /// Page / scene background.
    static let background = Color(red: 0.04, green: 0.08, blue: 0.16)

    /// Cards, list rows, sectioned content.
    static let surface = Color(red: 0.07, green: 0.12, blue: 0.22)

    /// Elevated surfaces inside cards (cell chips, code blocks).
    static let surfaceHigh = Color(red: 0.10, green: 0.16, blue: 0.28)

    /// Hairline separators on the navy background.
    static let divider = Color.white.opacity(0.08)

    /// Brand accent — matches the icon's heartbeat trace.
    static let accent = Color(red: 0.24, green: 0.91, blue: 0.46)

    /// Semantic colors. These are intentionally a touch brighter than the
    /// default `.red` / `.orange` so they remain legible on the deep navy.
    static let danger = Color(red: 1.00, green: 0.42, blue: 0.42)
    static let warning = Color(red: 1.00, green: 0.72, blue: 0.30)

    /// iOS 26's Liquid Glass design renders the nav bar as floating pills over
    /// content — forcing a solid `UINavigationBarAppearance` background hides
    /// the title. We leave the nav bar to the system (it picks up dark mode
    /// automatically via `.preferredColorScheme(.dark)`), and only tweak items
    /// that need explicit theming.
    static func applyUIKitAppearance() {
        // Intentionally empty for iOS 26. Add per-platform appearance tweaks
        // here if older iOS support is ever reintroduced.
    }
}
