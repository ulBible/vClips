import SwiftUI
import Sparkle
import vClipsCore

// The GitHub-release variant: Sparkle auto-updates and a donation link.
// The Mac App Store variant lives in Sources/vClipsAppStore (no Sparkle —
// the store owns updates — and no external donation link, per App Review
// guideline 3.1.1).

/// LSUIElement apps get Sparkle's modal alerts behind other windows, and the
/// invisible modal blocks the whole app — menu and hotkey included (verified
/// live in Badasseo against a failing update feed). Activate right before
/// any modal shows so it always fronts.
final class UpdaterUIDelegate: NSObject, SPUStandardUserDriverDelegate {
    func standardUserDriverWillShowModalAlert() {
        // Sparkle delivers user-driver callbacks on the main thread; the
        // protocol just isn't annotated, so bridge the isolation explicitly.
        MainActor.assumeIsolated {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let env = AppEnvironment()
    /// Sparkle auto-updates, fed by appcast.xml on the GitHub "latest" release
    /// (SUFeedURL in Info.plist). Started eagerly so background update checks
    /// run on the interval Sparkle persists in user defaults.
    let updaterController: SPUStandardUpdaterController
    // Sparkle holds the user-driver delegate weakly — keep it alive here.
    private let updaterUIDelegate: UpdaterUIDelegate

    override init() {
        let uiDelegate = UpdaterUIDelegate()
        self.updaterUIDelegate = uiDelegate
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil,
            userDriverDelegate: uiDelegate)
        super.init()
    }

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
