import SwiftUI
import SwiftData

@MainActor
final class PopupViewModel: ObservableObject {
    @Published var query: String = "" { didSet { refresh() } }
    /// Selection is tracked by item identity, not by list position, so
    /// reordering (pin toggles, searches, captures) can never silently move
    /// it onto a different item.
    @Published private(set) var selectedID: PersistentIdentifier?
    /// The row the view should scroll to. Only keyboard navigation and popup
    /// reset set this — pin/unpin/delete deliberately leave the viewport
    /// alone so bulk actions at the end of a long list don't yank the scroll
    /// position back to the top after every click.
    @Published private(set) var scrollTarget: PersistentIdentifier?
    /// Pinned items, shown under the PINNED header (empty while searching).
    @Published private(set) var favorites: [ClipItem] = []
    /// Unpinned items (or, while searching, the full matching list, pinned first).
    @Published private(set) var recents: [ClipItem] = []

    /// Flat display order (favorites + recents).
    var results: [ClipItem] { favorites + recents }

    var selectedItem: ClipItem? {
        results.first { $0.persistentModelID == selectedID }
    }

    private let store: HistoryStore
    private let onChoose: (ClipItem) -> Void

    init(store: HistoryStore, onChoose: @escaping (ClipItem) -> Void) {
        self.store = store
        self.onChoose = onChoose
    }

    /// Called when the popup opens: clear the query and return selection to the top.
    func reset() {
        query = ""  // didSet runs refresh()
        selectedID = results.first?.persistentModelID
        scrollTarget = selectedID
    }

    func refresh() {
        let all = store.search(query)
        if query.isEmpty {
            favorites = all.filter { $0.isPinned }
            recents = all.filter { !$0.isPinned }
        } else {
            // While searching, present a single list (already pinned-first sorted).
            favorites = []
            recents = all
        }
        if selectedItem == nil {
            selectedID = results.first?.persistentModelID
        }
    }

    func isSelected(_ item: ClipItem) -> Bool {
        item.persistentModelID == selectedID
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.persistentModelID == selectedID } ?? 0
        let next = min(max(current + delta, 0), results.count - 1)
        selectedID = results[next].persistentModelID
        scrollTarget = selectedID
    }

    func choose(_ item: ClipItem) {
        onChoose(item)
    }

    func togglePin(_ item: ClipItem) {
        store.togglePin(item)
        refresh()
        // Pinning moves the item between sections; keep the selection on it.
        selectedID = item.persistentModelID
    }

    func delete(_ item: ClipItem) {
        let wasSelected = isSelected(item)
        // Pick the neighbor to inherit the selection before the list changes.
        let successorID: PersistentIdentifier? = {
            guard let index = results.firstIndex(where: { $0.persistentModelID == item.persistentModelID }) else { return nil }
            if index + 1 < results.count { return results[index + 1].persistentModelID }
            if index > 0 { return results[index - 1].persistentModelID }
            return nil
        }()
        store.delete(item)
        refresh()
        if wasSelected {
            selectedID = successorID ?? results.first?.persistentModelID
        }
    }

    // Keyboard variants operating on the current selection.
    func chooseSelected() {
        if let selectedItem { choose(selectedItem) }
    }

    func togglePinSelected() {
        if let selectedItem { togglePin(selectedItem) }
    }

    func deleteSelected() {
        if let selectedItem { delete(selectedItem) }
    }
}
