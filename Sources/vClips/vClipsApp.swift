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
            Button("History (⌘⇧V)") {
                appDelegate.env.togglePopup()
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
        .menuBarExtraStyle(.menu)
    }
}
