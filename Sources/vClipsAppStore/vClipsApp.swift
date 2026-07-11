import SwiftUI
import vClipsCore

// The Mac App Store variant: sandboxed, no Sparkle (the store owns updates),
// and no external donation link (App Review guideline 3.1.1 forbids steering
// to outside payment). Everything else is vClipsCore, shared with the GitHub
// variant in Sources/vClips.

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
            SettingsView(showsSupportLink: false)
        }
    }
}
