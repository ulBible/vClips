import SwiftUI

@main
struct vClipsApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        MenuBarExtra("vClips", systemImage: "doc.on.clipboard") {
            Button("History (⌘⇧V)") {
                // PopupController.toggle() wired in Task 4.
            }
            Divider()
            Button("Quit vClips") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: scenePhaseProxy) { }
    }

    // Trigger env.start() once at launch.
    private var scenePhaseProxy: Int {
        env.start()
        return 0
    }
}
