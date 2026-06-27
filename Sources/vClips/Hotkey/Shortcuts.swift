import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global hotkey that opens the clipboard history popup. Defaults to ⌘⇧V,
    /// matching the original fixed shortcut. User changes are stored in
    /// UserDefaults by KeyboardShortcuts automatically.
    static let togglePopup = Self("togglePopup", default: .init(.v, modifiers: [.command, .shift]))
}
