import SwiftUI
import vClipsCore

// The Mac App Store variant: sandboxed, no Sparkle (the store owns updates),
// and no external donation link (App Review guideline 3.1.1 forbids steering
// to outside payment). Everything else is vClipsCore, shared with the GitHub
// variant in Sources/vClips.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Copy-only on the App Store: guideline 2.4.5 disallows Accessibility-
    // based paste synthesis, so this variant never offers auto-paste.
    let env = AppEnvironment(autoPasteCapable: false)

    func applicationDidFinishLaunching(_ notification: Notification) {
        env.start()
    }
}

@main
struct vClipsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("vClips", systemImage: "doc.on.clipboard") {
            MenuContent(env: appDelegate.env, showsSupportLink: false)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(showsSupportLink: false)
        }
    }
}
