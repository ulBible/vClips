import AppKit
import Carbon.HIToolbox
import CoreGraphics

@MainActor
final class Paster {
    private let monitor: ClipboardMonitor

    init(monitor: ClipboardMonitor) {
        self.monitor = monitor
    }

    func paste(_ content: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
        monitor.markSelfCopy()

        guard AccessibilityPermission.isTrusted else {
            // Copy-only fallback; on the first occurrence, explain how to
            // enable auto-paste (never prompted at launch).
            AutoPasteOffer.offerIfNeeded()
            return
        }
        // Wait for the popup to close and focus to return to the previous app
        // before synthesizing ⌘V, so the keystroke lands in that app.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            self.synthesizeCommandV()
        }
    }

    private func synthesizeCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyUp?.flags = .maskCommand

        // Session tap, not HID: the App Sandbox blocks posting at the HID
        // level, while session-level synthetic events are allowed (given
        // Accessibility). Non-sandboxed builds behave identically either way.
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
