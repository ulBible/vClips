import Carbon.HIToolbox
import CoreGraphics

/// Synthetic keystrokes, moved out of vClipsCore so CoreGraphics event
/// posting is only ever linked into the direct-distribution build.
enum KeystrokeSynthesizer {
    /// Presses ⌘V in whatever app is frontmost. Returns false when the events
    /// could not be created, so the caller can fall back to the copy toast.
    @discardableResult
    static func commandV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return false }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Session tap, not HID: the App Sandbox blocks posting at the HID
        // level, while session-level synthetic events are allowed (given
        // Accessibility). Non-sandboxed builds behave identically either way.
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        return true
    }
}
