import SwiftUI

struct CellGridView: View {
    let cells: [Double]
    let updatedAt: Date?

    private var minV: Double { cells.min() ?? 0 }
    private var maxV: Double { cells.max() ?? 0 }
    private var avgV: Double {
        guard !cells.isEmpty else { return 0 }
        return cells.reduce(0, +) / Double(cells.count)
    }
    private var deltaMv: Int { Int(((maxV - minV) * 1000).rounded()) }

    private var deltaColor: Color {
        switch deltaMv {
        case ..<30: .green
        case ..<80: .orange
        default: .red
        }
    }

    private var columns: [GridItem] {
        // Aim for 4 cells per row, scaling down to 3 if many cells.
        let count = cells.count
        let per = count <= 4 ? count : (count <= 8 ? 4 : (count <= 12 ? 4 : 5))
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: max(per, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cells").font(.headline)
                Spacer()
                if let updatedAt {
                    Text(updatedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 12) {
                Stat(label: "min", value: String(format: "%.3f V", minV))
                Stat(label: "max", value: String(format: "%.3f V", maxV))
                Stat(label: "avg", value: String(format: "%.3f V", avgV))
                Stat(label: "Δ", value: "\(deltaMv) mV", tint: deltaColor)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { idx, v in
                    CellChip(index: idx + 1, voltage: v, min: minV, max: maxV, avg: avgV)
                }
            }
        }
        .cardStyle()
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout).fontWeight(.medium).monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CellChip: View {
    let index: Int
    let voltage: Double
    let min: Double
    let max: Double
    let avg: Double

    private var deviationMv: Int { Int(((voltage - avg) * 1000).rounded()) }

    private var color: Color {
        if voltage == min, max - min > 0.01 { return .red }
        if voltage == max, max - min > 0.01 { return .blue }
        return .secondary
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("C\(index)").font(.caption2).foregroundStyle(.tertiary)
            Text(String(format: "%.3f", voltage))
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.medium)
            Text(String(format: "%+d mV", deviationMv))
                .font(.caption2).monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.surfaceHigh)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color.opacity(voltage == min || voltage == max ? 0.6 : 0), lineWidth: 1.5)
                )
        )
    }
}
