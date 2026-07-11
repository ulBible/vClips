import SwiftUI
import KeyboardShortcuts

enum SupportLinks {
    // TODO: placeholder until the donation account exists — update before the
    // first public release (GitHub Sponsors / Ko-fi / Buy Me a Coffee).
    static let donation = URL(string: "https://github.com/sponsors/ulBible")!
}

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

            Divider()

            HStack {
                Text("vClips is free.")
                    .foregroundStyle(.secondary)
                Link("Support development ❤️", destination: SupportLinks.donation)
            }
            .font(.callout)
        }
        .padding(20)
        .frame(width: 360)
    }
}
