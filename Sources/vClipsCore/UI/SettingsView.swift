import SwiftUI
import KeyboardShortcuts

enum SupportLinks {
    // Goes live once the GitHub Sponsors profile is approved & published.
    static let donation = URL(string: "https://github.com/sponsors/ulBible")!
}

public struct SettingsView: View {
    /// The App Store build passes `false`: App Review guideline 3.1.1 forbids
    /// linking out to external payment, so the donation row must not ship there.
    private let showsSupportLink: Bool
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    /// Marks the onChange fired by our own revert below so it isn't treated
    /// as a user action. Guarding on live SMAppService status instead would
    /// swallow real toggles: a self-signed app can sit in .requiresApproval
    /// (isEnabled false) while still registered, making OFF a no-op forever.
    @State private var revertingLaunchAtLogin = false

    public init(showsSupportLink: Bool = true) {
        self.showsSupportLink = showsSupportLink
    }

    public var body: some View {
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

            if showsSupportLink {
                Divider()

                HStack {
                    Text("vClips is free.")
                        .foregroundStyle(.secondary)
                    Link("Support development ❤️", destination: SupportLinks.donation)
                }
                .font(.callout)
            }
        }
        .padding(20)
        // Size the window to fit the content: a fixed width clipped both the
        // recorder's leading label and the support link's trailing emoji.
        .fixedSize()
    }
}
