import XCTest
@testable import vClipsCore

final class PasterActionTests: XCTestCase {
    func testCopyOnlyWheneverNotCapable() {
        XCTAssertEqual(Paster.action(autoPasteCapable: false, trusted: true), .copyOnly)
        XCTAssertEqual(Paster.action(autoPasteCapable: false, trusted: false), .copyOnly)
    }

    func testSynthesizeOnlyWhenCapableAndTrusted() {
        XCTAssertEqual(Paster.action(autoPasteCapable: true, trusted: true), .synthesize)
        XCTAssertEqual(Paster.action(autoPasteCapable: true, trusted: false), .copyOnly)
    }
}
