import ApplicationServices
import AppKit

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt asking the user to grant Accessibility access.
    static func prompt() {
        // "AXTrustedCheckOptionPrompt" is the stable string value of kAXTrustedCheckOptionPrompt.
        // Using the literal avoids Swift 6's shared-mutable-state error on the CFStringRef global.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
