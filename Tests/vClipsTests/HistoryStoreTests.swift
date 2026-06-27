import XCTest
import SwiftData
@testable import vClips

@MainActor
final class HistoryStoreTests: XCTestCase {
    private func makeStore() throws -> HistoryStore {
        try HistoryStore(container: ModelContainerFactory.inMemory())
    }

    func test_capture_addsItem() throws {
        let store = try makeStore()
        store.capture("hello")
        XCTAssertEqual(store.search("").map(\.content), ["hello"])
    }

    func test_capture_ignoresEmptyAndWhitespace() throws {
        let store = try makeStore()
        store.capture("")
        store.capture("   \n\t ")
        XCTAssertTrue(store.search("").isEmpty)
    }

    func test_capture_duplicateContentDedupesAndBumps() throws {
        let store = try makeStore()
        store.capture("a")
        store.capture("b")
        store.capture("a") // duplicate of first
        let all = store.search("")
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.content, "a") // bumped to top by lastUsedAt
    }

    func test_capture_trimsWhitespaceAndDedupesAcrossWhitespaceVariants() throws {
        let store = try makeStore()
        store.capture("hello ")
        store.capture("hello")
        let all = store.search("")
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.content, "hello") // stored trimmed
    }

    func test_search_isCaseInsensitiveSubstring() throws {
        let store = try makeStore()
        store.capture("Hello World")
        store.capture("goodbye")
        XCTAssertEqual(store.search("hello").map(\.content), ["Hello World"])
    }

    func test_search_ordersPinnedFirstThenRecent() throws {
        let store = try makeStore()
        store.capture("old")
        store.capture("recent")
        let old = store.search("").first { $0.content == "old" }!
        store.togglePin(old)
        XCTAssertEqual(store.search("").map(\.content), ["old", "recent"])
    }

    func test_cleanup_keepsMaxUnpinnedDroppingOldest() throws {
        let store = try makeStore()
        for i in 0..<(store.maxUnpinned + 5) {
            store.capture("item-\(i)")
        }
        let all = store.search("")
        XCTAssertEqual(all.count, store.maxUnpinned)
        XCTAssertFalse(all.contains { $0.content == "item-0" }) // oldest dropped
        XCTAssertTrue(all.contains { $0.content == "item-\(store.maxUnpinned + 4)" })
    }

    func test_cleanup_exemptsPinnedItems() throws {
        let store = try makeStore()
        store.capture("keep-me")
        let pinned = store.search("").first!
        store.togglePin(pinned)
        for i in 0..<(store.maxUnpinned + 5) {
            store.capture("filler-\(i)")
        }
        XCTAssertTrue(store.search("").contains { $0.content == "keep-me" })
    }
}
