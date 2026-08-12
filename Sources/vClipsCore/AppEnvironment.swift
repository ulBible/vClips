import SwiftUI
import SwiftData
import KeyboardShortcuts

@MainActor
public final class AppEnvironment: ObservableObject {
    let container: ModelContainer
    let store: HistoryStore
    let monitor: ClipboardMonitor
    private(set) var paster: Paster!
    private(set) var popup: PopupController!
    private(set) var viewModel: PopupViewModel!
    /// false in the Mac App Store build: auto-paste (and every mention of
    /// Accessibility) is compiled in but unreachable there. Injected from the
    /// entry points, mirroring MenuContent/SettingsView's showsSupportLink.
    public let autoPasteCapable: Bool

    public init(autoPasteCapable: Bool = true) {
        self.autoPasteCapable = autoPasteCapable
        let container = try! ModelContainerFactory.onDisk()
        self.container = container
        let store = HistoryStore(container: container)
        self.store = store
        self.monitor = ClipboardMonitor { content in
            store.capture(content)
        }
        self.paster = Paster(monitor: self.monitor, autoPasteCapable: autoPasteCapable)

        self.viewModel = PopupViewModel(store: store, onChoose: { [weak self] item in
            self?.choose(item)
        })
        self.popup = PopupController(rootView: { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(PopupView(
                model: self.viewModel,
                pasteKeyHintLabel: autoPasteCapable ? "Paste" : "Copy",
                onEscape: { self.popup.hide() },
                onContentChange: { self.popup.resizeToFit() }
            ))
        })
        // Only while the query is empty: with text present, ⌘⌫ must stay the
        // search field's "delete to beginning of line".
        self.popup.onCommandDelete = { [weak self] in
            guard let self, self.viewModel.query.isEmpty else { return false }
            withAnimation(.snappy(duration: 0.25)) { self.viewModel.deleteSelected() }
            return true
        }
    }

    public func start() {
        monitor.start()
        KeyboardShortcuts.onKeyDown(for: .togglePopup) { [weak self] in
            self?.togglePopup()
        }
        // Deliberately no Accessibility prompt here: the permission is offered
        // contextually on the first paste attempt instead (AutoPasteOffer),
        // matching the pattern of Mac App Store clipboard managers and App
        // Review's expectation that the permission stays optional.
    }

    public func togglePopup() {
        viewModel.reset()
        popup.toggle()
    }

    private func choose(_ item: ClipItem) {
        popup.hide()
        store.markUsed(item)
        paster.paste(item.content)
    }
}
