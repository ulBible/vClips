import SwiftUI
import Sparkle
import vClipsCore

// The GitHub-release variant: Sparkle auto-updates and a donation link.
// The Mac App Store variant lives in Sources/vClipsAppStore (no Sparkle —
// the store owns updates — and no external donation link, per App Review
// guideline 3.1.1).

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
            MenuContent(env: appDelegate.env) { [weak appDelegate] in
                appDelegate?.updaterController.updater.checkForUpdates()
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}
