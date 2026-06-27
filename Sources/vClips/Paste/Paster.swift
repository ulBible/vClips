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
            return // copy-only fallback; user pastes manually with ⌘V
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

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
