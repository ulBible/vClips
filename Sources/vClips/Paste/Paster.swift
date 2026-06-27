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
        synthesizeCommandV()
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
