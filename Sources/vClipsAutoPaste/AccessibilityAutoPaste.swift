import AppKit
import vClipsCore

/// The direct-distribution auto-paste engine. This type — and everything it
/// touches — is only linked into the `vClips` executable; the Mac App Store
/// executable depends on vClipsCore alone, so the AX symbols and the
/// user-facing Accessibility wording never reach that binary
/// (scripts/appstore.sh enforces it with nm/strings).
@MainActor
public struct AccessibilityAutoPaste: AutoPasteEngine {
    public init() {}
    public var isTrusted: Bool { AccessibilityPermission.isTrusted }
    public func offerIfNeeded() -> Bool { AutoPasteOffer.offerIfNeeded() }
    @discardableResult public func synthesize() -> Bool { KeystrokeSynthesizer.commandV() }
    public var grantMenuTitle: String { "Grant Accessibility (for auto-paste)…" }
    public func openSystemSettings() { AccessibilityPermission.openSettings() }
}
