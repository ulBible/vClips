import XCTest
@testable import vClipsCore

final class CopyToastTests: XCTestCase {
    private let key = "showCopyToast"

    override func setUp() { UserDefaults.standard.removeObject(forKey: key) }
    override func tearDown() { UserDefaults.standard.removeObject(forKey: key) }

    func testEnabledByDefault() {
        XCTAssertTrue(CopyToast.isEnabled)
    }

    func testDisabledWhenPreferenceOff() {
        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(CopyToast.isEnabled)
    }
}
