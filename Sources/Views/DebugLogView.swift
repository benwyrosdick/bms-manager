import SwiftUI
import UIKit

struct DebugLogView: View {
    @ObservedObject private var logger = BLELogger.shared
    @State private var filter: BLELogger.Category? = nil
    // When non-nil, the displayed log is frozen at this snapshot — new
    // entries still arrive in the logger but they don't render until the user
    // resumes. When nil, the view follows the live entry stream.
    @State private var pausedSnapshot: [BLELogger.Entry]?
    @State private var jumpRequested = 0

    private var isPaused: Bool { pausedSnapshot != nil }

    /// Entries to display: the frozen snapshot when paused, else the live log.
    /// Filter is applied on top so changing categories while paused still works.
    private var displayed: [BLELogger.Entry] {
        let source = pausedSnapshot ?? logger.entries
        guard let filter else { return source }
        return source.filter { $0.category == filter }
    }

    var body: some View {
        let entries = displayed
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
                        // Only auto-follow while not paused; when paused, lastID
                        // is the frozen snapshot's tail and doesn't change anyway.
                        if !isPaused, let newID {
                            withAnimation(.linear(duration: 0.1)) {
                                proxy.scrollTo(newID, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: jumpRequested) { _, _ in
                        if let lastID {
                            withAnimation(.linear(duration: 0.15)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
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
                    Button {
                        if isPaused {
                            pausedSnapshot = nil
                            jumpRequested += 1
                        } else {
                            // Freeze the full logger entries; filter is re-applied
                            // at render time so category chips still work paused.
                            pausedSnapshot = logger.entries
                        }
                    } label: {
                        Label(
                            isPaused ? "Paused" : "Following",
                            systemImage: isPaused ? "pause.circle.fill" : "play.circle.fill"
                        )
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                        .foregroundStyle(isPaused ? Theme.warning : Theme.accent)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            jumpRequested += 1
                        } label: {
                            Label("Jump to latest", systemImage: "arrow.down.to.line")
                        }
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
