import AppKit

/// One-time, contextual Accessibility onboarding, shown the first time the
/// user pastes without the permission — direct-distribution build only (this
/// whole target is absent from the MAS binary, which has no engine at all).
/// Never prompts at launch; stays copy-only if declined.
@MainActor
enum AutoPasteOffer {
    private static let offeredKey = "didOfferAutoPaste"

    /// Returns true when the one-time offer fires. The alert's message text
    /// already says "copied — press ⌘V", so the caller skips the copy toast
    /// for that one paste.
    @discardableResult
    static func offerIfNeeded(present: @escaping @MainActor () -> Void = presentAlert) -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: offeredKey) else { return false }
        defaults.set(true, forKey: offeredKey)

        // Let the popup finish closing and focus settle before taking key
        // status for the alert.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            present()
        }
        return true
    }

    private static func presentAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Your clip was copied — press ⌘V to paste it"
        alert.informativeText = """
        vClips can also paste the selected clip into the app you're \
        using, automatically. To enable auto-paste, allow vClips under \
        System Settings → Privacy & Security → Accessibility. \
        vClips only ever uses this to press ⌘V for you.
        """
        alert.addButton(withTitle: "Enable Auto-Paste…")
        alert.addButton(withTitle: "Use Copy Only")
        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityPermission.prompt()
        }
    }
}
