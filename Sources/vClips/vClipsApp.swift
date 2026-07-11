import SwiftUI
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let env = AppEnvironment()
    /// Sparkle auto-updates, fed by appcast.xml on the GitHub "latest" release
    /// (SUFeedURL in Info.plist). Started eagerly so background update checks
    /// run on the interval Sparkle persists in user defaults.
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        env.start()
    }
}

@main
struct vClipsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("vClips", systemImage: "doc.on.clipboard") {
            MenuContent(env: appDelegate.env, updater: appDelegate.updaterController.updater)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

/// The status-bar menu. Split into its own view so it can read the
/// `openSettings` environment action, which is the supported way to open the
/// Settings scene (the private `showSettingsWindow:` selector does nothing here).
private struct MenuContent: View {
    let env: AppEnvironment
    let updater: SPUUpdater
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("History") {
            env.togglePopup()
        }
        Button("Check for Updates…") {
            // Same LSUIElement caveat as Settings: activate first so the
            // update dialog appears in front of the user's current app.
            NSApp.activate(ignoringOtherApps: true)
            updater.checkForUpdates()
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
