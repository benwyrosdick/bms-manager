import SwiftUI
import UIKit

struct DebugLogView: View {
    @ObservedObject private var logger = BLELogger.shared
    @State private var filter: BLELogger.Category? = nil
    @State private var autoscroll = true

    private var filtered: [BLELogger.Entry] {
        guard let filter else { return logger.entries }
        return logger.entries.filter { $0.category == filter }
    }

    var body: some View {
        let entries = filtered
        let lastID = entries.last?.id
        return NavigationStack {
            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Theme.surface)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(entries) { entry in
                                LogRow(entry: entry).id(entry.id)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: lastID) { _, newID in
                        if autoscroll, let newID {
                            withAnimation(.linear(duration: 0.1)) {
                                proxy.scrollTo(newID, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .themedNavigation()
            .navigationTitle("Debug log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle("Auto", isOn: $autoscroll)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Copy all") { copyAll() }
                        Button("Clear", role: .destructive) { logger.clear() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isOn: filter == nil) { filter = nil }
                ForEach(BLELogger.Category.allCases, id: \.rawValue) { cat in
                    FilterChip(label: cat.rawValue.capitalized, isOn: filter == cat) {
                        filter = (filter == cat) ? nil : cat
                    }
                }
            }
        }
    }

    private func copyAll() {
        UIPasteboard.general.string = logger.dumpText()
    }
}

private struct FilterChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption).fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isOn ? Color.accentColor : Theme.surfaceHigh)
                )
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct LogRow: View {
    let entry: BLELogger.Entry

    private var color: Color {
        switch entry.level {
        case .debug: .secondary
        case .info: .primary
        case .warn: .orange
        case .error: .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.formattedTime)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(entry.level.symbol)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.category.rawValue)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 4)
                        .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 3))
                    if let p = entry.peripheral {
                        Text(String(p.suffix(8)))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(entry.message)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(color)
                    .textSelection(.enabled)
            }
        }
    }
}
