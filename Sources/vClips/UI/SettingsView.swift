import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Open clipboard popup:", name: .togglePopup)
        }
        .padding(20)
        .frame(width: 360)
    }
}
