import AppKit
import Carbon.HIToolbox
import CoreGraphics

@MainActor
final class Paster {
    /// Which way a paste request resolves. Pure decision, kept static so the
    /// matrix is unit-testable without AppKit.
    enum Action: Equatable { case copyOnly, synthesize }

    nonisolated static func action(autoPasteCapable: Bool, trusted: Bool) -> Action {
        (autoPasteCapable && trusted) ? .synthesize : .copyOnly
    }

    private let monitor: ClipboardMonitor
    /// false in the Mac App Store build: the AX/synthesis path is unreachable.
    private let autoPasteCapable: Bool

    init(monitor: ClipboardMonitor, autoPasteCapable: Bool = true) {
        self.monitor = monitor
        self.autoPasteCapable = autoPasteCapable
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
