import XCTest
@testable import vClipsCore

@MainActor
final class AutoPasteOfferTests: XCTestCase {
    private let key = "didOfferAutoPaste"

    override func setUp() { UserDefaults.standard.removeObject(forKey: key) }
    override func tearDown() { UserDefaults.standard.removeObject(forKey: key) }

    func testFiresExactlyOnce() {
        XCTAssertTrue(AutoPasteOffer.offerIfNeeded(present: {}))
        XCTAssertFalse(AutoPasteOffer.offerIfNeeded(present: {}))
    }
}
