import SwiftUI

@MainActor
final class PopupViewModel: ObservableObject {
    @Published var query: String = "" { didSet { refresh() } }
    @Published var selectedIndex: Int = 0
    @Published private(set) var results: [ClipItem] = []

    private let store: HistoryStore
    private let onChoose: (ClipItem) -> Void

    init(store: HistoryStore, onChoose: @escaping (ClipItem) -> Void) {
        self.store = store
        self.onChoose = onChoose
    }

    func refresh() {
        results = store.search(query)
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

    private func clampSelection() {
        if results.isEmpty { selectedIndex = 0; return }
        selectedIndex = min(max(selectedIndex, 0), results.count - 1)
    }
}
