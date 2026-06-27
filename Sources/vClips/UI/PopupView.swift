import SwiftUI
import AppKit

struct PopupView: View {
    @ObservedObject var model: PopupViewModel
    let onEscape: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search clipboard…", text: $model.query)
                .textFieldStyle(.plain)
                .padding(8)
                .focused($searchFocused)
                .onSubmit { model.chooseSelected() }

            Divider()

            ScrollViewReader { proxy in
                List(Array(model.results.enumerated()), id: \.offset) { index, item in
                    HStack {
                        if item.isPinned { Image(systemName: "pin.fill").font(.caption) }
                        Text(item.content)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(index == model.selectedIndex
                                       ? Color.accentColor.opacity(0.25) : Color.clear)
                    .id(index)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectedIndex = index
                        model.chooseSelected()
                    }
                }
                .onChange(of: model.selectedIndex) { _, new in
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
        .frame(width: 380, height: 420)
        .onAppear { searchFocused = true }
        // On the first popup after launch the panel becomes key asynchronously
        // (the accessory app activates ~100ms later), so the onAppear focus is
        // lost. Re-assert focus the moment the window actually becomes key.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            searchFocused = true
        }
        .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
        .onKeyPress(.return) { model.chooseSelected(); return .handled }
        .onKeyPress(.escape) { onEscape(); return .handled }
        .onKeyPress(keys: ["f"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            model.togglePinSelected(); return .handled
        }
    }
}
