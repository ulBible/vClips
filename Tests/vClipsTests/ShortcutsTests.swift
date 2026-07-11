import XCTest
import KeyboardShortcuts
@testable import vClipsCore

final class ShortcutsTests: XCTestCase {
    func test_togglePopup_defaultIsCommandShiftV() {
        XCTAssertEqual(
            KeyboardShortcuts.Name.togglePopup.defaultShortcut,
            KeyboardShortcuts.Shortcut(.v, modifiers: [.command, .shift])
        )
    }
}
