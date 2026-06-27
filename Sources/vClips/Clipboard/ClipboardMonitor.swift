import AppKit

@MainActor
final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private let onCapture: (String) -> Void
    private var timer: Timer?
    private var lastChangeCount: Int

    init(pasteboard: NSPasteboard = .general,
         interval: TimeInterval = 0.5,
         onCapture: @escaping (String) -> Void) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.onCapture = onCapture
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call right after the app itself writes to the pasteboard so the next
    /// change is not re-captured as a new copy.
    func markSelfCopy() {
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard PasteboardPolicy.shouldCapture(types: types) else { return }
        guard let string = pasteboard.string(forType: .string),
              !string.isEmpty else { return }
        onCapture(string)
    }
}
