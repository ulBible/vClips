import XCTest
import SwiftData
@testable import vClips

@MainActor
final class SingleFavoriteRepro: XCTestCase {
    private func makeStore() throws -> HistoryStore {
        try HistoryStore(container: ModelContainerFactory.inMemory())
    }

    func test_unpin_onlyFavorite_noRecents() throws {
        let store = try makeStore()
        store.capture("solo")
        store.togglePin(store.search("").first!)
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.refresh()
        XCTAssertEqual(vm.favorites.count, 1)
        vm.togglePinSelected()
        XCTAssertEqual(vm.favorites.count, 0)
        XCTAssertEqual(vm.recents.map(\.content), ["solo"])
    }

    func test_delete_onlyFavorite_noRecents() throws {
        let store = try makeStore()
        store.capture("solo")
        store.togglePin(store.search("").first!)
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.refresh()
        vm.deleteSelected()
        XCTAssertEqual(vm.results.count, 0)
        XCTAssertEqual(vm.selectedIndex, 0)
    }

    func test_unpin_onlyFavorite_withRecents() throws {
        let store = try makeStore()
        store.capture("recent1")
        store.capture("fav")
        store.togglePin(store.search("").first { $0.content == "fav" }!)
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.refresh() // results: [fav, recent1], selected 0 = fav
        vm.togglePinSelected()
        XCTAssertEqual(vm.favorites.count, 0)
        XCTAssertEqual(vm.recents.count, 2)
    }

    func test_delete_onlyFavorite_withRecents() throws {
        let store = try makeStore()
        store.capture("recent1")
        store.capture("fav")
        store.togglePin(store.search("").first { $0.content == "fav" }!)
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.refresh()
        vm.deleteSelected()
        XCTAssertEqual(vm.results.map(\.content), ["recent1"])
    }
}
