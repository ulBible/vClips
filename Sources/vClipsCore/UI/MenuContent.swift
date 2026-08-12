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
    /// The App Store build passes `false` — no external donation links there
    /// (App Review guideline 3.1.1); mirrors SettingsView's parameter.
    private let showsSupportLink: Bool
    @Environment(\.openSettings) private var openSettings

    public init(env: AppEnvironment, checkForUpdates: (() -> Void)? = nil,
                showsSupportLink: Bool = true) {
        self.env = env
        self.checkForUpdates = checkForUpdates
        self.showsSupportLink = showsSupportLink
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
        Button("About vClips") {
            AboutPanel.show(showsSupportLink: showsSupportLink)
        }
        // Absent from the MAS build: there is no engine there, and both the
        // AX call and the item's wording live in the vClipsAutoPaste target.
        if let engine = env.autoPasteEngine, !engine.isTrusted {
            Divider()
            Button(engine.grantMenuTitle) { engine.openSystemSettings() }
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
