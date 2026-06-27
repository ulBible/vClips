import SwiftUI
import SwiftData

@MainActor
final class AppEnvironment: ObservableObject {
    let container: ModelContainer
    let store: HistoryStore
    let monitor: ClipboardMonitor
    private(set) var paster: Paster!
    private(set) var popup: PopupController!
    private(set) var hotkey: HotkeyManager!
    private(set) var viewModel: PopupViewModel!

    init() {
        let container = try! ModelContainerFactory.onDisk()
        self.container = container
        let store = HistoryStore(container: container)
        self.store = store
        self.monitor = ClipboardMonitor { content in
            store.capture(content)
        }
        self.paster = Paster(monitor: self.monitor)

        self.viewModel = PopupViewModel(store: store, onChoose: { [weak self] item in
            self?.choose(item)
        })
        self.popup = PopupController(rootView: { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(PopupView(model: self.viewModel, onEscape: { self.popup.hide() }))
        })
        self.hotkey = HotkeyManager(onTrigger: { [weak self] in self?.togglePopup() })
    }

    func start() {
        monitor.start()
        hotkey.register()
        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.prompt()
        }
    }

    func togglePopup() {
        viewModel.query = ""
        viewModel.refresh()
        popup.toggle()
    }

    private func choose(_ item: ClipItem) {
        popup.hide()
        store.markUsed(item)
        paster.paste(item.content)
    }
}
