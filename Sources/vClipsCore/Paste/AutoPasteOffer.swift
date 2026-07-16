import AppKit

/// One-time, contextual Accessibility onboarding, shown the first time the
/// user pastes without the permission — the pattern established by Mac App
/// Store clipboard managers (e.g. Paste): never prompt at launch, explain at
/// the moment the feature matters, and stay copy-only if declined. The
/// menu-bar "Grant Accessibility…" item remains for enabling it later.
@MainActor
enum AutoPasteOffer {
    private static let offeredKey = "didOfferAutoPaste"

    static func offerIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: offeredKey) else { return }
        defaults.set(true, forKey: offeredKey)

        // Let the popup finish closing and focus settle before taking key
        // status for the alert.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
}
