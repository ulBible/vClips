import Combine
import SwiftData

@MainActor
final class AppEnvironment: ObservableObject {
    let container: ModelContainer
    let store: HistoryStore
    let monitor: ClipboardMonitor

    init() {
        // SwiftData container is required for the app to function.
        let container = try! ModelContainerFactory.onDisk()
        self.container = container
        let store = HistoryStore(container: container)
        self.store = store
        self.monitor = ClipboardMonitor { content in
            store.capture(content)
        }
    }

    func start() {
        monitor.start()
        // HotkeyManager.start() wired in Task 4.
        // Paster wired in Task 5.
    }
}
