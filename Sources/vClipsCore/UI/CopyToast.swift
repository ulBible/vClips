import AppKit
import SwiftUI

/// A small non-activating HUD shown after a copy that did NOT auto-paste:
/// the whole MAS (copy-only) build, and the direct build's no-permission
/// fallback. Never takes focus; repeated copies reuse the panel and restart
/// the timer instead of stacking.
@MainActor
final class CopyToast {
    static let shared = CopyToast()

    /// Settings toggle ("showCopyToast"), default ON.
    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "showCopyToast") as? Bool ?? true
    }

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String = "Copied — press ⌘V to paste") {
        guard Self.isEnabled else { return }
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel

        let host = NSHostingView(rootView: ToastLabel(text: text))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        if let screen = NSScreen.main {
            let area = screen.visibleFrame   // below the menu bar
            panel.setFrameOrigin(NSPoint(
                x: area.midX - panel.frame.width / 2,
                y: area.maxY - panel.frame.height - 12))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, let panel = self?.panel else { return }
            await NSAnimationContext.runAnimationGroup {
                $0.duration = 0.25
                panel.animator().alphaValue = 0
            }
            try? await Task.sleep(for: .milliseconds(260))
            if !Task.isCancelled { panel.orderOut(nil) }
        }
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false          // the capsule material carries its own edge
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        return p
    }
}

private struct ToastLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(8)   // room for the material's soft edge
    }
}
