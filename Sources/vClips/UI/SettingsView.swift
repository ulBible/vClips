import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Open clipboard popup:", name: .togglePopup)

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    // Ignore the no-op change when we revert the toggle below.
                    guard enabled != LaunchAtLogin.isEnabled else { return }
                    do {
                        try LaunchAtLogin.set(enabled: enabled)
                        launchAtLoginError = nil
                    } catch {
                        launchAtLogin = LaunchAtLogin.isEnabled
                        launchAtLoginError = error.localizedDescription
                    }
                }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
