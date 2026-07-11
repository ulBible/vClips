import SwiftUI

/// The status-bar menu, shared by both distribution variants. The App Store
/// build passes no `checkForUpdates` (updates come from the store), which
/// hides the item; the GitHub build wires it to Sparkle. Split into its own
/// view so it can read the `openSettings` environment action, which is the
/// supported way to open the Settings scene (the private
/// `showSettingsWindow:` selector does nothing here).
public struct MenuContent: View {
    private let env: AppEnvironment
    private let checkForUpdates: (() -> Void)?
    @Environment(\.openSettings) private var openSettings

    public init(env: AppEnvironment, checkForUpdates: (() -> Void)? = nil) {
        self.env = env
        self.checkForUpdates = checkForUpdates
    }

    public var body: some View {
        Button("History") {
            env.togglePopup()
        }
        if let checkForUpdates {
            Button("Check for Updates…") {
                // Same LSUIElement caveat as Settings: activate first so the
                // update dialog appears in front of the user's current app.
                NSApp.activate(ignoringOtherApps: true)
                checkForUpdates()
            }
        }
        Button("Settings…") {
            // As an LSUIElement accessory, vClips is never the active app on its
            // own, so the Settings window otherwise opens *behind* whatever the
            // user is looking at. Activate first, then raise the window.
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
            raiseSettingsWindow()
        }
        if !AccessibilityPermission.isTrusted {
            Divider()
            Button("Grant Accessibility (for auto-paste)…") {
                AccessibilityPermission.openSettings()
            }
        }
        Divider()
        Button("Quit vClips") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Brings the Settings scene window to the front. `openSettings()` creates
    /// the window asynchronously, so poll briefly (up to ~1s) until it exists.
    /// Matching falls back to the window title because the identifier is a
    /// private SwiftUI detail that a macOS update may rename.
    private func raiseSettingsWindow(attemptsLeft: Int = 20) {
        let settings = NSApp.windows.first {
            $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
                || $0.title == "vClips Settings"
        }
        if let settings {
            settings.makeKeyAndOrderFront(nil)
        } else if attemptsLeft > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                raiseSettingsWindow(attemptsLeft: attemptsLeft - 1)
            }
        }
    }
}
