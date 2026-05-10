import SwiftUI

struct StatCard: View {
    let label: String
    let value: String
    var icon: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).foregroundStyle(tint) }
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.title3).fontWeight(.semibold).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SOCBar: View {
    let percent: Double
    var height: CGFloat = 12

    private var color: Color {
        switch percent {
        case ..<20: .red
        case ..<50: .orange
        default: .green
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(percent / 100, 1)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

struct StatGrid: View {
    let stats: BatteryStats

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(label: "Voltage", value: Format.volts(stats.voltage), icon: "bolt.fill", tint: .yellow)
            StatCard(
                label: "Current",
                value: Format.amps(stats.current),
                icon: stats.isCharging ? "arrow.down.circle.fill" : (stats.isDischarging ? "arrow.up.circle.fill" : "minus.circle.fill"),
                tint: stats.isCharging ? .green : (stats.isDischarging ? .orange : .secondary)
            )
            StatCard(label: "Power", value: Format.watts(stats.powerWatts), icon: "gauge.with.dots.needle.bottom.50percent", tint: .blue)
            StatCard(
                label: stats.isCharging ? "Time to full" : (stats.isDischarging ? "Time to empty" : "Idle"),
                value: stats.isCharging
                    ? (stats.timeToFull.map(Format.duration) ?? "—")
                    : (stats.isDischarging ? (stats.timeToEmpty.map(Format.duration) ?? "—") : "—"),
                icon: "clock.fill",
                tint: .purple
            )
            StatCard(label: "Cycles", value: Format.cycles(stats.cycleCount), icon: "arrow.triangle.2.circlepath", tint: .indigo)
            StatCard(
                label: "Temperature",
                value: stats.maxTemperatureC.map(Format.tempC) ?? "—",
                icon: "thermometer.medium",
                tint: .red
            )
            StatCard(
                label: "Remaining",
                value: Format.ah(stats.remainingCapacityAh),
                icon: "battery.50",
                tint: .teal
            )
            StatCard(
                label: "Capacity",
                value: Format.ah(stats.nominalCapacityAh),
                icon: "tray.full",
                tint: .secondary
            )
        }
    }
}
