import XCTest
@testable import vClipsCore

final class PasterActionTests: XCTestCase {
    func testCopyOnlyWithoutEngine() {
        XCTAssertEqual(Paster.action(hasEngine: false, trusted: true), .copyOnly)
        XCTAssertEqual(Paster.action(hasEngine: false, trusted: false), .copyOnly)
    }

    func testSynthesizeOnlyWithEngineAndTrusted() {
        XCTAssertEqual(Paster.action(hasEngine: true, trusted: true), .synthesize)
        XCTAssertEqual(Paster.action(hasEngine: true, trusted: false), .copyOnly)
    }
}
