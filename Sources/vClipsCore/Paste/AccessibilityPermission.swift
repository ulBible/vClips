import ApplicationServices
import AppKit

public enum AccessibilityPermission {
    public static var isTrusted: Bool {
        // Test hook: `defaults write com.vclips.app SimulateUntrusted -bool true`
        // exercises the copy-only path and the AutoPasteOffer dialog without
        // resetting the real TCC grant (tccutil would hit the user's install).
        if UserDefaults.standard.bool(forKey: "SimulateUntrusted") { return false }
        return AXIsProcessTrusted()
    }

    /// Shows the system prompt asking the user to grant Accessibility access.
    static func prompt() {
        // "AXTrustedCheckOptionPrompt" is the stable string value of kAXTrustedCheckOptionPrompt.
        // Using the literal avoids Swift 6's shared-mutable-state error on the CFStringRef global.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public static func openSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
