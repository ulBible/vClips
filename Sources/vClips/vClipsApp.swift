import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let env = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        env.start()
    }
}

@main
struct vClipsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("vClips", systemImage: "doc.on.clipboard") {
            MenuContent(env: appDelegate.env)
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
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("History") {
            env.togglePopup()
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
    /// the window asynchronously, so retry on the next run-loop turns until it
    /// exists rather than looking exactly once.
    private func raiseSettingsWindow(attemptsLeft: Int = 10) {
        let settings = NSApp.windows.first {
            $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
        }
        if let settings {
            settings.makeKeyAndOrderFront(nil)
        } else if attemptsLeft > 0 {
            DispatchQueue.main.async { raiseSettingsWindow(attemptsLeft: attemptsLeft - 1) }
        }
    }
}
