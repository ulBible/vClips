import SwiftUI
import AppKit

struct PopupView: View {
    @ObservedObject var model: PopupViewModel
    let onEscape: () -> Void
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
        .frame(width: 420)
        .frame(minHeight: 220, maxHeight: 480)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .onAppear { searchFocused = true }
        // First popup after launch becomes key asynchronously; re-assert focus then.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            searchFocused = true
        }
        .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
        .onKeyPress(.return) { model.chooseSelected(); return .handled }
        .onKeyPress(.escape) { onEscape(); return .handled }
        .onKeyPress(keys: ["f"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            model.togglePinSelected(); return .handled
        }
        // ⌘⌫ deletes the selected item. Bare ⌫ is left for editing the search field.
        .onKeyPress(keys: [.delete]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            model.deleteSelected(); return .handled
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

    private var listBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !model.favorites.isEmpty {
                        sectionHeader("FAVORITES", symbol: "star.fill")
                        ForEach(Array(model.favorites.enumerated()), id: \.element.persistentModelID) { offset, item in
                            row(item, flatIndex: offset)
                        }
                    }
                    if !model.recents.isEmpty {
                        if !model.favorites.isEmpty || model.query.isEmpty {
                            sectionHeader(
                                model.query.isEmpty ? "RECENT" : "RESULTS",
                                symbol: model.query.isEmpty ? "clock" : "magnifyingglass"
                            )
                        }
                        ForEach(Array(model.recents.enumerated()), id: \.element.persistentModelID) { offset, item in
                            row(item, flatIndex: model.favorites.count + offset)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.selectedIndex) { _, new in
                if model.results.indices.contains(new) {
                    proxy.scrollTo(model.results[new].persistentModelID, anchor: .center)
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

    private func row(_ item: ClipItem, flatIndex: Int) -> some View {
        RowView(
            item: item,
            isSelected: flatIndex == model.selectedIndex,
            onTap: { model.selectedIndex = flatIndex; model.chooseSelected() },
            onTogglePin: { model.selectedIndex = flatIndex; model.togglePinSelected() },
            onDelete: { model.selectedIndex = flatIndex; model.deleteSelected() }
        )
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

    private var previewText: String? {
        guard model.results.indices.contains(model.selectedIndex) else { return nil }
        let content = model.results[model.selectedIndex].content
        let isLong = content.count > 60 || content.contains("\n")
        return isLong ? content : nil
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
                Text(text)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 76)
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
    @State private var hovering = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.dateTimeStyle = .named
        return f
    }()

    private var contentType: ContentType { ContentType.detect(item.content) }

    var body: some View {
        HStack(spacing: 10) {
            // Tap target for select/paste — kept separate from the action buttons
            // so clicking ★/× doesn't also fire the row tap (which would paste & close).
            HStack(spacing: 10) {
                iconChip
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.content.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isSelected ? .white : .primary)
                    Text("\(contentType.label) · \(Self.relativeFormatter.localizedString(for: item.lastUsedAt, relativeTo: Date()))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.8))
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            if isSelected || hovering {
                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "star.fill" : "star")
                        .foregroundStyle(item.isPinned ? Color.yellow : (isSelected ? Color.white.opacity(0.8) : Color.secondary))
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unfavorite (⌘F)" : "Favorite (⌘F)")

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete (⌘⌫)")
            } else if item.isPinned {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : (hovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        .onHover { hovering = $0 }
    }

    private var iconChip: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                LinearGradient(
                    colors: [chipTint.opacity(0.85), chipTint],
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

    private var chipTint: Color {
        switch contentType {
        case .url: return .blue
        case .email: return .green
        case .filePath: return .orange
        case .text: return Color(nsColor: .systemGray)
        }
    }
}
