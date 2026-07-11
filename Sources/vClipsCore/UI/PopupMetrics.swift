import Foundation

/// Popup geometry shared by the SwiftUI content (PopupView) and the AppKit
/// panel (PopupController) — the two must agree or the border ring and blur
/// mask drift apart.
enum PopupMetrics {
    static let width: CGFloat = 420
    static let minHeight: CGFloat = 220
    static let maxHeight: CGFloat = 480
    static let cornerRadius: CGFloat = 14
}
