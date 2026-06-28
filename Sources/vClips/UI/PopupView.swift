import SwiftUI
import AppKit

struct PopupView: View {
    @ObservedObject var model: PopupViewModel
    let onEscape: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().opacity(0.5)
            if model.results.isEmpty {
                emptyState
            } else {
                listBody
            }
            if let preview = previewText {
                Divider().opacity(0.5)
                previewPane(preview)
            }
        }
        .frame(width: 380)
        .frame(minHeight: 200, maxHeight: 460)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clipboard…", text: $model.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { model.chooseSelected() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var listBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !model.favorites.isEmpty {
                        sectionHeader("FAVORITES")
                        ForEach(Array(model.favorites.enumerated()), id: \.element.persistentModelID) { offset, item in
                            row(item, flatIndex: offset)
                        }
                    }
                    if !model.recents.isEmpty {
                        if !model.favorites.isEmpty || model.query.isEmpty {
                            sectionHeader(model.query.isEmpty ? "RECENT" : "RESULTS")
                        }
                        ForEach(Array(model.recents.enumerated()), id: \.element.persistentModelID) { offset, item in
                            row(item, flatIndex: model.favorites.count + offset)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .onChange(of: model.selectedIndex) { _, new in
                if model.results.indices.contains(new) {
                    proxy.scrollTo(model.results[new].persistentModelID, anchor: .center)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
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
        VStack {
            Spacer()
            Text(model.query.isEmpty ? "No clipboard history yet" : "No matches")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var previewText: String? {
        guard model.results.indices.contains(model.selectedIndex) else { return nil }
        let content = model.results[model.selectedIndex].content
        let isLong = content.count > 60 || content.contains("\n")
        return isLong ? content : nil
    }

    private func previewPane(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: 90)
    }
}

private struct RowView: View {
    let item: ClipItem
    let isSelected: Bool
    let onTap: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            // Tap target for select/paste — kept separate from the action buttons
            // so clicking ★/× doesn't also fire the row tap (which would paste & close).
            HStack(spacing: 8) {
                Image(systemName: ContentType.detect(item.content).symbolName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(item.content.replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            if isSelected || hovering {
                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "star.fill" : "star")
                        .foregroundStyle(item.isPinned ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unfavorite (⌘F)" : "Favorite (⌘F)")

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete (⌘⌫)")
            } else if item.isPinned {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.30) : Color.clear)
        )
        .onHover { hovering = $0 }
    }
}
