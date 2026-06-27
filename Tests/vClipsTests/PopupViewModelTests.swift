import XCTest
import SwiftData
@testable import vClips

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
        XCTAssertEqual(vm.selectedIndex, 0)
        vm.moveSelection(-1)
        XCTAssertEqual(vm.selectedIndex, 0)   // clamped at top
        vm.moveSelection(1)
        XCTAssertEqual(vm.selectedIndex, 1)
        vm.moveSelection(1)
        XCTAssertEqual(vm.selectedIndex, 1)   // clamped at bottom
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
}
