import XCTest
import SwiftData
@testable import vClips

@MainActor
final class HistoryStoreDeleteTests: XCTestCase {
    private func makeStore() throws -> HistoryStore {
        try HistoryStore(container: ModelContainerFactory.inMemory())
    }

    func test_delete_removesUnpinnedItem() throws {
        let store = try makeStore()
        store.capture("a")
        store.capture("b")
        let b = store.search("").first { $0.content == "b" }!
        store.delete(b)
        XCTAssertEqual(store.search("").map(\.content), ["a"])
    }

    func test_delete_removesPinnedItem() throws {
        let store = try makeStore()
        store.capture("keep")
        let item = store.search("").first!
        store.togglePin(item)
        store.delete(item)
        XCTAssertTrue(store.search("").isEmpty)
    }
}
