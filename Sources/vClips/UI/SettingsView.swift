import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    /// Marks the onChange fired by our own revert below so it isn't treated
    /// as a user action. Guarding on live SMAppService status instead would
    /// swallow real toggles: a self-signed app can sit in .requiresApproval
    /// (isEnabled false) while still registered, making OFF a no-op forever.
    @State private var revertingLaunchAtLogin = false

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Open clipboard popup:", name: .togglePopup)

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    if revertingLaunchAtLogin { revertingLaunchAtLogin = false; return }
                    do {
                        try LaunchAtLogin.set(enabled: enabled)
                        launchAtLoginError = nil
                    } catch {
                        launchAtLoginError = error.localizedDescription
                        let actual = LaunchAtLogin.isEnabled
                        if launchAtLogin != actual {
                            revertingLaunchAtLogin = true
                            launchAtLogin = actual
                        }
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
