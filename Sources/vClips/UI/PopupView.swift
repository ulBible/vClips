import SwiftUI
import AppKit

struct PopupView: View {
    @ObservedObject var model: PopupViewModel
    let onEscape: () -> Void
    /// Called when the amount of content changes so the panel can re-fit its
    /// height to the SwiftUI ideal size.
    let onContentChange: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().opacity(0.4)
            if model.results.isEmpty {
                emptyState
            } else {
                listBody
            }
            if let preview = previewText {
                Divider().opacity(0.4)
                previewPane(preview)
            }
            Divider().opacity(0.4)
            footer
        }
        .frame(width: PopupMetrics.width)
        .frame(minHeight: PopupMetrics.minHeight, maxHeight: PopupMetrics.maxHeight)
        .overlay(
            RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .onAppear { searchFocused = true }
        .onChange(of: model.results.count) { _, _ in onContentChange() }
        .onChange(of: model.favorites.count) { _, _ in onContentChange() }
        // First popup after launch becomes key asynchronously; re-assert focus then.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            searchFocused = true
        }
        .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
        .onKeyPress(.return) { model.chooseSelected(); return .handled }
        .onKeyPress(.escape) { onEscape(); return .handled }
        .background {
            // ⌘-modified keys never reach onKeyPress — AppKit routes them
            // through the key-equivalent chain before keyDown — so the pin
            // and delete shortcuts are hidden buttons with real keyboard
            // shortcuts instead.
            // ⌘⌫ is NOT here: keyboardShortcut(.delete) never matches the
            // hardware delete key, so PopupController handles it with an
            // NSEvent monitor instead.
            Button("") { animateListChange { model.togglePinSelected() } }
                .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search clipboard…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
                .onSubmit { model.chooseSelected() }
            Button(action: onEscape) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// One flat entry list (headers + rows) rendered by a single ForEach.
    /// A pin toggle then reorders rows *within* one container instead of
    /// moving them between two ForEach containers — a cross-container move
    /// with the same identity left stale "selected" row renderings behind
    /// in the LazyVStack (multiple highlight pills after repeated toggles).
    private enum ListEntry: Identifiable {
        case header(String, symbol: String)
        case item(ClipItem)

        var id: AnyHashable {
            switch self {
            case .header(let title, _): return "header-\(title)"
            case .item(let item): return item.persistentModelID
            }
        }
    }

    private var listEntries: [ListEntry] {
        var entries: [ListEntry] = []
        if !model.favorites.isEmpty {
            entries.append(.header("PINNED", symbol: "pin.fill"))
            entries.append(contentsOf: model.favorites.map(ListEntry.item))
        }
        if !model.recents.isEmpty {
            if model.query.isEmpty {
                entries.append(.header("RECENT", symbol: "clock"))
            }
            entries.append(contentsOf: model.recents.map(ListEntry.item))
        }
        return entries
    }

    private var listBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(listEntries) { entry in
                        switch entry {
                        case .header(let title, let symbol):
                            sectionHeader(title, symbol: symbol)
                        case .item(let item):
                            row(item)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.scrollTarget) { _, new in
                if let new {
                    proxy.scrollTo(AnyHashable(new), anchor: .center)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 8, weight: .semibold))
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: ClipItem) -> some View {
        RowView(
            item: item,
            isSelected: model.isSelected(item),
            onTap: { model.choose(item) },
            onTogglePin: { animateListChange { model.togglePin(item) } },
            onDelete: { animateListChange { model.delete(item) } }
        )
    }

    /// Pin toggles and deletes animate so the affected row visibly slides to
    /// its new place (or fades out) instead of teleporting. Search filtering
    /// deliberately stays instant — animating rows on every keystroke reads
    /// as lag, not feedback.
    private func animateListChange(_ change: () -> Void) {
        withAnimation(.snappy(duration: 0.25)) { change() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: model.query.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "No clipboard history yet" : "No matches")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if model.query.isEmpty {
                Text("Copy something and it will show up here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    /// The full content of the selected item. The preview pane is a fixed,
    /// always-present slot — appearing only for long items made the list
    /// area grow and shrink while moving the selection, which was jarring.
    private var previewText: String? {
        model.selectedItem?.content
    }

    private func previewPane(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("PREVIEW")
                Spacer()
                Text("\(text.count) characters")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            ScrollView {
                // Cap what gets laid out — rendering a multi-MB clip into the
                // 76pt pane stutters on every selection move.
                Text(text.count > 2000 ? String(text.prefix(2000)) + "\u{2026}" : text)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 76)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(model.results.count == 1 ? "1 item" : "\(model.results.count) items")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            KeyHint(key: "⏎", label: "Paste")
            KeyHint(key: "⌘F", label: "Pin")
            KeyHint(key: "⌘⌫", label: "Delete")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

/// A "⌘F Pin"-style keycap + label pair for the footer hint bar.
private struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct RowView: View {
    let item: ClipItem
    let isSelected: Bool
    let onTap: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    /// Detected once per row value — the computed form re-ran the regex three
    /// times (label, icon, tint) on every body evaluation.
    private let contentType: ContentType
    @State private var hovering = false

    init(
        item: ClipItem,
        isSelected: Bool,
        onTap: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.onTap = onTap
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
        self.contentType = ContentType.detect(item.content)
    }

    private var showsActions: Bool { isSelected || hovering }

    // System-paired selection colors stay legible for any accent (yellow,
    // graphite, …) where hardcoded white-on-accent loses contrast.
    private static let selectionBackground = Color(nsColor: .selectedContentBackgroundColor)
    private static let selectionText = Color(nsColor: .alternateSelectedControlTextColor)

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.dateTimeStyle = .named
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            // Tap target for select/paste — kept separate from the action buttons
            // so clicking ★/× doesn't also fire the row tap (which would paste & close).
            HStack(spacing: 10) {
                iconChip
                VStack(alignment: .leading, spacing: 1) {
                    // lineLimit(1) shows ~60 chars; bounding the input avoids
                    // copying multi-MB clips on every render.
                    Text(String(item.content.prefix(200)).replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isSelected ? Self.selectionText : Color.primary)
                    Text("\(contentType.label) · \(Self.relativeFormatter.localizedString(for: item.lastUsedAt, relativeTo: Date()))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(isSelected ? Self.selectionText.opacity(0.7) : Color.secondary.opacity(0.8))
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            // The action slots stay in the layout permanently (hidden via
            // opacity) so the row never reflows when they appear — buttons
            // shifting under the cursor caused misclicks.
            Button(action: onTogglePin) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(item.isPinned ? Color.yellow : (isSelected ? Self.selectionText.opacity(0.8) : Color.secondary))
                    // Explicit hit box: the bare glyph (~15pt) left dead zones
                    // around the visible icon, so edge clicks did nothing.
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(showsActions || item.isPinned ? 1 : 0)
            // Clickable whenever visible. Hover alone is not enough: when a
            // row slides under a stationary cursor (e.g. after unpinning the
            // favorite above it), macOS sends no mouseEntered, so a visible
            // star would silently swallow clicks.
            .allowsHitTesting(showsActions || item.isPinned)
            .help(item.isPinned ? "Unpin (⌘F)" : "Pin (⌘F)")

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(isSelected ? Self.selectionText.opacity(0.8) : Color.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(showsActions ? 1 : 0)
            .allowsHitTesting(showsActions)
            .help("Delete (⌘⌫)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Self.selectionBackground : (hovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        // Transparent regions don't hit-test, so without an explicit shape
        // the hover only triggers over the text/icons — not the whole row.
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var iconChip: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                LinearGradient(
                    colors: [contentType.tint.opacity(0.85), contentType.tint],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: contentType.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }

}
