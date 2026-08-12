import Foundation

/// Everything Accessibility-flavored lives behind this seam, implemented in
/// the direct-distribution-only vClipsAutoPaste target. The Mac App Store
/// build injects nil, so no AX symbol or string is even LINKED there —
/// guideline 2.4.5 compliance is structural, not a runtime convention.
@MainActor
public protocol AutoPasteEngine {
    var isTrusted: Bool { get }
    /// One-time explainer; true = it fired for this copy (caller skips the toast).
    func offerIfNeeded() -> Bool
    /// Synthesizes ⌘V into the frontmost app. Returns false if event creation failed.
    @discardableResult func synthesize() -> Bool
    /// Title + action for the status-bar "grant" menu item (string must live
    /// OUTSIDE vClipsCore so it never enters the MAS binary).
    var grantMenuTitle: String { get }
    func openSystemSettings()
}
