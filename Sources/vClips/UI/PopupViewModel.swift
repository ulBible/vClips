import SwiftUI

@MainActor
final class PopupViewModel: ObservableObject {
    @Published var query: String = "" { didSet { refresh() } }
    @Published var selectedIndex: Int = 0
    /// Pinned items, shown under the FAVORITES header (empty while searching).
    @Published private(set) var favorites: [ClipItem] = []
    /// Unpinned items (or, while searching, the full matching list, pinned first).
    @Published private(set) var recents: [ClipItem] = []
    /// Flat display order (favorites + recents); `selectedIndex` indexes this.
    @Published private(set) var results: [ClipItem] = []

    private let store: HistoryStore
    private let onChoose: (ClipItem) -> Void

    init(store: HistoryStore, onChoose: @escaping (ClipItem) -> Void) {
        self.store = store
        self.onChoose = onChoose
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
        results = favorites + recents
        clampSelection()
    }

    func moveSelection(_ delta: Int) {
        selectedIndex += delta
        clampSelection()
    }

    func chooseSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        onChoose(results[selectedIndex])
    }

    func togglePinSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        store.togglePin(results[selectedIndex])
        refresh()
    }

    func deleteSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        store.delete(results[selectedIndex])
        refresh()
    }

    private func clampSelection() {
        if results.isEmpty { selectedIndex = 0; return }
        selectedIndex = min(max(selectedIndex, 0), results.count - 1)
    }
}
