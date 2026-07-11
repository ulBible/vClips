import XCTest
import SwiftData
@testable import vClipsCore

@MainActor
final class PopupViewModelTests: XCTestCase {
    private func makeStore() throws -> HistoryStore {
        try HistoryStore(container: ModelContainerFactory.inMemory())
    }

    func test_refresh_loadsAllSortedResults() throws {
        let store = try makeStore()
        store.capture("one")
        store.capture("two")
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.refresh()
        XCTAssertEqual(vm.results.map(\.content), ["two", "one"])
    }

    func test_query_filtersResultsOnRefresh() throws {
        let store = try makeStore()
        store.capture("apple")
        store.capture("banana")
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.query = "app"
        vm.refresh()
        XCTAssertEqual(vm.results.map(\.content), ["apple"])
    }

    func test_moveSelection_clampsWithinBounds() throws {
        let store = try makeStore()
        store.capture("a")
        store.capture("b")
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.refresh()
        XCTAssertEqual(vm.selectedItem?.content, "b")
        vm.moveSelection(-1)
        XCTAssertEqual(vm.selectedItem?.content, "b")   // clamped at top
        vm.moveSelection(1)
        XCTAssertEqual(vm.selectedItem?.content, "a")
        vm.moveSelection(1)
        XCTAssertEqual(vm.selectedItem?.content, "a")   // clamped at bottom
    }

    func test_chooseSelected_invokesCallbackWithSelectedItem() throws {
        let store = try makeStore()
        store.capture("first")
        store.capture("second")
        var chosen: String?
        let vm = PopupViewModel(store: store, onChoose: { chosen = $0.content })
        vm.refresh()
        vm.moveSelection(1)
        vm.chooseSelected()
        XCTAssertEqual(chosen, "first") // index 1 == older "first"
    }

    func test_togglePinSelected_pinsAndReordersOnRefresh() throws {
        let store = try makeStore()
        store.capture("x")
        store.capture("y")
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.refresh()                 // ["y","x"], selected 0 == "y"
        vm.moveSelection(1)          // select "x"
        vm.togglePinSelected()
        vm.refresh()
        XCTAssertEqual(vm.results.first?.content, "x") // pinned to top
    }

    func test_refresh_splitsFavoritesAndRecents() throws {
        let store = try makeStore()
        store.capture("plain")
        store.capture("fav")
        let fav = store.search("").first { $0.content == "fav" }!
        store.togglePin(fav)
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.refresh()
        XCTAssertEqual(vm.favorites.map(\.content), ["fav"])
        XCTAssertEqual(vm.recents.map(\.content), ["plain"])
        XCTAssertEqual(vm.results.map(\.content), ["fav", "plain"]) // favorites first
    }

    func test_refresh_whileSearching_isSingleListNoFavoritesSection() throws {
        let store = try makeStore()
        store.capture("apple")
        store.capture("apricot")
        let apple = store.search("").first { $0.content == "apple" }!
        store.togglePin(apple)
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.query = "ap"
        vm.refresh()
        XCTAssertTrue(vm.favorites.isEmpty)
        XCTAssertEqual(vm.recents.map(\.content), ["apple", "apricot"]) // pinned first
        XCTAssertEqual(vm.results.count, 2)
    }

    func test_reset_clearsQueryAndReturnsSelectionToTop() throws {
        let store = try makeStore()
        store.capture("a")
        store.capture("b")
        store.capture("c")
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.query = "a"
        vm.moveSelection(0) // selection at 0 within filtered
        vm.refresh()
        vm.reset()
        XCTAssertEqual(vm.query, "")
        XCTAssertEqual(vm.selectedItem?.persistentModelID, vm.results.first?.persistentModelID)
        XCTAssertEqual(vm.results.count, 3) // full list restored
    }

    func test_deleteSelected_removesItemAndClampsSelection() throws {
        let store = try makeStore()
        store.capture("one")
        store.capture("two") // results: ["two","one"], selected 0
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.refresh()
        vm.moveSelection(1) // select index 1 == "one"
        vm.deleteSelected()
        XCTAssertEqual(vm.results.map(\.content), ["two"])
        XCTAssertEqual(vm.selectedItem?.content, "two") // selection moves to the neighbor
    }
}
