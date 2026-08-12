import AppKit

@MainActor
final class Paster {
    /// Which way a paste request resolves. Pure decision, kept static so the
    /// matrix is unit-testable without AppKit.
    enum Action: Equatable { case copyOnly, synthesize }

    nonisolated static func action(hasEngine: Bool, trusted: Bool) -> Action {
        (hasEngine && trusted) ? .synthesize : .copyOnly
    }

    private let monitor: ClipboardMonitor
    /// nil in the Mac App Store build: nothing Accessibility-flavored is even
    /// linked there (the engine lives in the vClipsAutoPaste target).
    private let engine: AutoPasteEngine?

    init(monitor: ClipboardMonitor, engine: AutoPasteEngine?) {
        self.monitor = monitor
        self.engine = engine
    }

    func paste(_ content: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
        monitor.markSelfCopy()

        // MAS build: engine is nil — nothing Accessibility-flavored is linked.
        guard let engine else { CopyToast.shared.show(); return }
        guard engine.isTrusted else {
            // Direct build only: the one-time explainer replaces the toast for
            // that single copy (its message already says "press ⌘V").
            if !engine.offerIfNeeded() { CopyToast.shared.show() }
            return
        }
        // Wait for the popup to close and focus to return to the previous app
        // before synthesizing ⌘V, so the keystroke lands in that app.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            if !engine.synthesize() { CopyToast.shared.show() }
        }
    }
}
