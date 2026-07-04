import AppKit
import SwiftUI

/// NSPanel that is allowed to become the key window even though the app is a
/// background (LSUIElement) accessory. Without this, keyboard input never
/// reaches the popup.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PopupController {
    private var panel: NSPanel?
    private var hostView: NSHostingView<AnyView>?
    private let makeRootView: () -> AnyView
    /// The app that was frontmost when the popup opened, restored on close so
    /// keyboard focus (and the auto-paste target) returns to where it was.
    private var previousApp: NSRunningApplication?

    init(rootView: @escaping () -> AnyView) {
        self.makeRootView = rootView
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        previousApp = NSWorkspace.shared.frontmostApplication
        fitPanelToContent()
        positionAtMouse(panel)
        // An accessory app must be activated for its window to become key, or
        // the first popup after launch receives no keyboard input at all.
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        // SwiftUI may apply pending model updates a run-loop turn later than
        // the fitting pass above; re-fit once they have landed.
        DispatchQueue.main.async { [weak self] in self?.fitPanelToContent() }
    }

    func hide() {
        panel?.orderOut(nil)
        // Return focus to the app the user was in, so a manual or synthesized
        // ⌘V lands there rather than in vClips.
        previousApp?.activate()
        previousApp = nil
    }

    /// Sizes the panel to the SwiftUI content's ideal height so a short
    /// history doesn't sit in a mostly-blank full-height window. Safe to call
    /// from SwiftUI updates: the frame change is deferred to the next
    /// run-loop turn.
    func resizeToFit() {
        DispatchQueue.main.async { [weak self] in self?.fitPanelToContent() }
    }

    private func fitPanelToContent() {
        guard let panel, let hostView else { return }
        let ideal = hostView.fittingSize
        let height = min(max(ideal.height, PopupMetrics.minHeight), PopupMetrics.maxHeight)
        guard abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - height  // keep the top edge fixed
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }

    private func makePanel() -> NSPanel {
        // No .titled: KeyablePanel forces canBecomeKey, so we don't need a title
        // bar — dropping it removes the empty strip above the search field.
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: PopupMetrics.width, height: PopupMetrics.maxHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear

        // .popover adapts to light/dark appearance, unlike the always-dark
        // .hudWindow, so the popup matches the system look in both modes.
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = PopupMetrics.cornerRadius
        effect.layer?.masksToBounds = true

        let host = NSHostingView(rootView: makeRootView())
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        panel.contentView = effect
        self.hostView = host
        return panel
    }

    private func positionAtMouse(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
    }
}
