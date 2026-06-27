# vClips Clipboard Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS-native, menu-bar-resident clipboard manager with text history, search, and favorites, summoned anywhere via ⌘⇧V, that auto-pastes the chosen item into the previously focused app.

**Architecture:** A SwiftPM executable target wrapped into a `.app` bundle (no `.xcodeproj`). A polling `ClipboardMonitor` feeds captured text into a SwiftData-backed `HistoryStore`. A Carbon global hotkey shows a nonactivating `NSPanel` hosting a SwiftUI popup; selecting an item routes through a `Paster` that sets the pasteboard and synthesizes ⌘V via CGEvent. All persistence is local; no network.

**Tech Stack:** Swift 6.3 (SwiftUI, SwiftData, AppKit), Carbon.HIToolbox (global hotkey), CoreGraphics (CGEvent), ApplicationServices (Accessibility). Build via Swift Package Manager + a bundling script. Requires full Xcode (SwiftData macros are absent from Command Line Tools).

## Global Constraints

- **Full Xcode required** — Command Line Tools alone cannot compile SwiftData (`@Model` macro plugin `SwiftDataMacros` ships only with Xcode). `xcode-select` must point at `/Applications/Xcode.app/Contents/Developer`. Task 0 gates all others.
- **Minimum deployment target:** macOS 14 (SwiftData + `View.onKeyPress` availability). Build SDK is macOS 26.5.
- **No external SwiftPM dependencies** — only system frameworks.
- **App is menu-bar-only:** `LSUIElement = true` (no Dock icon, no main window).
- **Privacy:** never persist pasteboard items marked `org.nspasteboard.ConcealedType` or `org.nspasteboard.TransientType`. No network calls anywhere.
- **Defaults (verbatim):** polling interval `0.5s`; max unpinned history `200`; global hotkey `⌘⇧V`; content type captured `.string` only.
- **Bundle identifier:** `com.vclips.app`. Executable/product name: `vClips`.
- **Commit after every task.**

---

## File Structure

```
vClips/
├── Package.swift                       # SwiftPM executable + test targets
├── scripts/
│   └── bundle.sh                       # builds release binary, wraps into vClips.app
├── Resources/
│   └── Info.plist                      # LSUIElement, bundle id, app metadata
├── Sources/vClips/
│   ├── vClipsApp.swift                 # @main App, MenuBarExtra, AppDelegate wiring
│   ├── AppEnvironment.swift            # composition root: builds container + components
│   ├── Models/
│   │   └── ClipItem.swift              # @Model: content, createdAt, isPinned, lastUsedAt
│   ├── Store/
│   │   ├── HistoryStore.swift          # capture/search/pin/cleanup over ModelContext
│   │   └── ModelContainerFactory.swift # on-disk + in-memory container builders
│   ├── Clipboard/
│   │   ├── ClipboardMonitor.swift      # changeCount polling, self-copy suppression
│   │   └── PasteboardPolicy.swift      # pure shouldCapture(types:) decision
│   ├── Hotkey/
│   │   └── HotkeyManager.swift         # Carbon RegisterEventHotKey wrapper
│   ├── Paste/
│   │   ├── Paster.swift                # set pasteboard + synthesize ⌘V
│   │   └── AccessibilityPermission.swift # AXIsProcessTrusted + prompt + settings link
│   └── UI/
│       ├── PopupController.swift       # NSPanel (nonactivating) lifecycle + placement
│       ├── PopupView.swift             # SwiftUI search field + results list
│       └── PopupViewModel.swift        # search text → results, selection index, actions
└── Tests/vClipsTests/
    ├── HistoryStoreTests.swift
    ├── PasteboardPolicyTests.swift
    └── PopupViewModelTests.swift
```

---

## Task 0: Environment prerequisite — install & select Xcode

**This task is performed by the user (manual) with verification by the implementer. No code.**

**Files:** none.

- [ ] **Step 1: Install Xcode**

Install Xcode from the Mac App Store (search "Xcode"). ~7GB+ download.

- [ ] **Step 2: Point the toolchain at Xcode**

Run:
```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -runFirstLaunch
```
Expected: license accepted, components installed, no error.

- [ ] **Step 3: Verify SwiftData macros now compile**

Run:
```bash
cat > /tmp/sd_smoke.swift <<'EOF'
import SwiftData
@Model final class Probe { var x: String = ""; init() {} }
print("swiftdata-ok")
EOF
xcrun swiftc /tmp/sd_smoke.swift -o /tmp/sd_smoke && /tmp/sd_smoke
```
Expected: prints `swiftdata-ok` (no `SwiftDataMacros ... not found` error).

- [ ] **Step 4: Confirm before proceeding**

Do not start Task 1 until Step 3 prints `swiftdata-ok`. If it still fails, stop and report — the rest of the plan cannot build.

---

## Task 1: Project scaffold + ClipItem model + HistoryStore

**Files:**
- Create: `Package.swift`
- Create: `Sources/vClips/Models/ClipItem.swift`
- Create: `Sources/vClips/Store/ModelContainerFactory.swift`
- Create: `Sources/vClips/Store/HistoryStore.swift`
- Create: `Sources/vClips/vClipsApp.swift` (temporary minimal `@main` so the executable target builds)
- Test: `Tests/vClipsTests/HistoryStoreTests.swift`

**Interfaces:**
- Produces:
  - `final class ClipItem` (`@Model`) with `var content: String`, `var createdAt: Date`, `var isPinned: Bool`, `var lastUsedAt: Date`, and `init(content: String)`.
  - `enum ModelContainerFactory { static func onDisk() throws -> ModelContainer; static func inMemory() throws -> ModelContainer }`
  - `final class HistoryStore` with `init(container: ModelContainer)`, `let maxUnpinned = 200`, and methods:
    - `func capture(_ content: String)`
    - `func search(_ query: String) -> [ClipItem]`
    - `func togglePin(_ item: ClipItem)`
    - `func markUsed(_ item: ClipItem)`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vClips",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "vClips",
            path: "Sources/vClips"
        ),
        .testTarget(
            name: "vClipsTests",
            dependencies: ["vClips"],
            path: "Tests/vClipsTests"
        ),
    ]
)
```

- [ ] **Step 2: Create `Sources/vClips/Models/ClipItem.swift`**

```swift
import Foundation
import SwiftData

@Model
final class ClipItem {
    var content: String
    var createdAt: Date
    var isPinned: Bool
    var lastUsedAt: Date

    init(content: String) {
        self.content = content
        let now = Date()
        self.createdAt = now
        self.isPinned = false
        self.lastUsedAt = now
    }
}
```

- [ ] **Step 3: Create `Sources/vClips/Store/ModelContainerFactory.swift`**

```swift
import Foundation
import SwiftData

enum ModelContainerFactory {
    static func onDisk() throws -> ModelContainer {
        let schema = Schema([ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func inMemory() throws -> ModelContainer {
        let schema = Schema([ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
```

- [ ] **Step 4: Create temporary `Sources/vClips/vClipsApp.swift`**

(Replaced in Task 3; needed now so the executable target compiles.)

```swift
import SwiftUI

@main
struct vClipsApp: App {
    var body: some Scene {
        // Placeholder scene; replaced with MenuBarExtra in Task 3.
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 5: Write the failing tests `Tests/vClipsTests/HistoryStoreTests.swift`**

```swift
import XCTest
import SwiftData
@testable import vClips

final class HistoryStoreTests: XCTestCase {
    private func makeStore() throws -> HistoryStore {
        try HistoryStore(container: ModelContainerFactory.inMemory())
    }

    func test_capture_addsItem() throws {
        let store = try makeStore()
        store.capture("hello")
        XCTAssertEqual(store.search("").map(\.content), ["hello"])
    }

    func test_capture_ignoresEmptyAndWhitespace() throws {
        let store = try makeStore()
        store.capture("")
        store.capture("   \n\t ")
        XCTAssertTrue(store.search("").isEmpty)
    }

    func test_capture_duplicateContentDedupesAndBumps() throws {
        let store = try makeStore()
        store.capture("a")
        store.capture("b")
        store.capture("a") // duplicate of first
        let all = store.search("")
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.content, "a") // bumped to top by lastUsedAt
    }

    func test_search_isCaseInsensitiveSubstring() throws {
        let store = try makeStore()
        store.capture("Hello World")
        store.capture("goodbye")
        XCTAssertEqual(store.search("hello").map(\.content), ["Hello World"])
    }

    func test_search_ordersPinnedFirstThenRecent() throws {
        let store = try makeStore()
        store.capture("old")
        store.capture("recent")
        let old = store.search("").first { $0.content == "old" }!
        store.togglePin(old)
        XCTAssertEqual(store.search("").map(\.content), ["old", "recent"])
    }

    func test_cleanup_keepsMaxUnpinnedDroppingOldest() throws {
        let store = try makeStore()
        for i in 0..<(store.maxUnpinned + 5) {
            store.capture("item-\(i)")
        }
        let all = store.search("")
        XCTAssertEqual(all.count, store.maxUnpinned)
        XCTAssertFalse(all.contains { $0.content == "item-0" }) // oldest dropped
        XCTAssertTrue(all.contains { $0.content == "item-\(store.maxUnpinned + 4)" })
    }

    func test_cleanup_exemptsPinnedItems() throws {
        let store = try makeStore()
        store.capture("keep-me")
        let pinned = store.search("").first!
        store.togglePin(pinned)
        for i in 0..<(store.maxUnpinned + 5) {
            store.capture("filler-\(i)")
        }
        XCTAssertTrue(store.search("").contains { $0.content == "keep-me" })
    }
}
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -20`
Expected: FAIL — `cannot find 'HistoryStore' in scope` (not yet created).

- [ ] **Step 7: Implement `Sources/vClips/Store/HistoryStore.swift`**

```swift
import Foundation
import SwiftData

@MainActor
final class HistoryStore {
    let maxUnpinned = 200
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    func capture(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = firstItem(withContent: content) {
            existing.lastUsedAt = Date()
            save()
            return
        }

        context.insert(ClipItem(content: content))
        save()
        cleanup()
    }

    func search(_ query: String) -> [ClipItem] {
        let items = (try? context.fetch(FetchDescriptor<ClipItem>())) ?? []
        let filtered: [ClipItem]
        if query.isEmpty {
            filtered = items
        } else {
            filtered = items.filter { $0.content.localizedCaseInsensitiveContains(query) }
        }
        return filtered.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            return lhs.lastUsedAt > rhs.lastUsedAt
        }
    }

    func togglePin(_ item: ClipItem) {
        item.isPinned.toggle()
        save()
    }

    func markUsed(_ item: ClipItem) {
        item.lastUsedAt = Date()
        save()
    }

    private func firstItem(withContent content: String) -> ClipItem? {
        let all = (try? context.fetch(FetchDescriptor<ClipItem>())) ?? []
        return all.first { $0.content == content }
    }

    private func cleanup() {
        let all = (try? context.fetch(FetchDescriptor<ClipItem>())) ?? []
        let unpinned = all.filter { !$0.isPinned }.sorted { $0.lastUsedAt > $1.lastUsedAt }
        guard unpinned.count > maxUnpinned else { return }
        for item in unpinned[maxUnpinned...] {
            context.delete(item)
        }
        save()
    }

    private func save() {
        try? context.save()
    }
}
```

- [ ] **Step 8: Make tests MainActor-compatible**

`HistoryStore` is `@MainActor`. Annotate the test class so calls are allowed. Edit `Tests/vClipsTests/HistoryStoreTests.swift` — change the class declaration line to:

```swift
@MainActor
final class HistoryStoreTests: XCTestCase {
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -20`
Expected: PASS — all `HistoryStoreTests` green.

- [ ] **Step 10: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: scaffold SwiftPM project with ClipItem model and HistoryStore"
```

---

## Task 2: Pasteboard capture policy + ClipboardMonitor

**Files:**
- Create: `Sources/vClips/Clipboard/PasteboardPolicy.swift`
- Create: `Sources/vClips/Clipboard/ClipboardMonitor.swift`
- Test: `Tests/vClipsTests/PasteboardPolicyTests.swift`

**Interfaces:**
- Consumes: `HistoryStore.capture(_:)` (Task 1).
- Produces:
  - `enum PasteboardPolicy { static let blockedTypes: Set<String>; static func shouldCapture(types: [String]) -> Bool }`
  - `final class ClipboardMonitor` with `init(pasteboard: NSPasteboard = .general, interval: TimeInterval = 0.5, onCapture: @escaping (String) -> Void)`, `func start()`, `func stop()`, `func markSelfCopy()`.

- [ ] **Step 1: Write the failing tests `Tests/vClipsTests/PasteboardPolicyTests.swift`**

```swift
import XCTest
@testable import vClips

final class PasteboardPolicyTests: XCTestCase {
    func test_allowsPlainTextTypes() {
        XCTAssertTrue(PasteboardPolicy.shouldCapture(types: ["public.utf8-plain-text"]))
    }

    func test_blocksConcealedType() {
        let types = ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]
        XCTAssertFalse(PasteboardPolicy.shouldCapture(types: types))
    }

    func test_blocksTransientType() {
        let types = ["org.nspasteboard.TransientType", "public.utf8-plain-text"]
        XCTAssertFalse(PasteboardPolicy.shouldCapture(types: types))
    }

    func test_blocksAutoGeneratedType() {
        let types = ["org.nspasteboard.AutoGeneratedType"]
        XCTAssertFalse(PasteboardPolicy.shouldCapture(types: types))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PasteboardPolicyTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'PasteboardPolicy' in scope`.

- [ ] **Step 3: Implement `Sources/vClips/Clipboard/PasteboardPolicy.swift`**

```swift
import Foundation

enum PasteboardPolicy {
    static let blockedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
    ]

    static func shouldCapture(types: [String]) -> Bool {
        for type in types where blockedTypes.contains(type) {
            return false
        }
        return true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PasteboardPolicyTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Implement `Sources/vClips/Clipboard/ClipboardMonitor.swift`**

(No unit test — depends on live `NSPasteboard`/timer; verified manually in Task 3.)

```swift
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
```

- [ ] **Step 6: Verify the whole package still builds**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat: add pasteboard capture policy and clipboard monitor"
```

---

## Task 3: App entry, menu bar, composition root, and .app bundling

**Files:**
- Modify: `Sources/vClips/vClipsApp.swift` (replace placeholder)
- Create: `Sources/vClips/AppEnvironment.swift`
- Create: `Resources/Info.plist`
- Create: `scripts/bundle.sh`

**Interfaces:**
- Consumes: `HistoryStore` (Task 1), `ClipboardMonitor` (Task 2). Forward-references `PopupController.toggle()` and `HotkeyManager` (Task 4) and `Paster` (Task 5) — wired in later tasks. This task wires only Store + Monitor and leaves a `// wired in Task 4/5` seam.
- Produces:
  - `@MainActor final class AppEnvironment: ObservableObject` exposing `let store: HistoryStore`, `let monitor: ClipboardMonitor`, and `func start()`.

- [ ] **Step 1: Create `Sources/vClips/AppEnvironment.swift`**

```swift
import SwiftUI
import SwiftData

@MainActor
final class AppEnvironment: ObservableObject {
    let container: ModelContainer
    let store: HistoryStore
    let monitor: ClipboardMonitor

    init() {
        // SwiftData container is required for the app to function.
        let container = try! ModelContainerFactory.onDisk()
        self.container = container
        let store = HistoryStore(container: container)
        self.store = store
        self.monitor = ClipboardMonitor { content in
            store.capture(content)
        }
    }

    func start() {
        monitor.start()
        // HotkeyManager.start() wired in Task 4.
        // Paster wired in Task 5.
    }
}
```

- [ ] **Step 2: Replace `Sources/vClips/vClipsApp.swift`**

```swift
import SwiftUI

@main
struct vClipsApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        MenuBarExtra("vClips", systemImage: "doc.on.clipboard") {
            Button("History (⌘⇧V)") {
                // PopupController.toggle() wired in Task 4.
            }
            Divider()
            Button("Quit vClips") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: scenePhaseProxy) { }
    }

    // Trigger env.start() once at launch.
    private var scenePhaseProxy: Int {
        env.start()
        return 0
    }
}
```

Note: `scenePhaseProxy` is a launch-time seam; replace with a cleaner `AppDelegate` hook if preferred. It calls `env.start()` exactly once because `body` is evaluated at startup.

- [ ] **Step 3: Create `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>vClips</string>
    <key>CFBundleDisplayName</key>
    <string>vClips</string>
    <key>CFBundleIdentifier</key>
    <string>com.vclips.app</string>
    <key>CFBundleExecutable</key>
    <string>vClips</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Personal use.</string>
</dict>
</plist>
```

- [ ] **Step 4: Create `scripts/bundle.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="vClips"
BUILD_DIR=".build/${CONFIG}"
APP_BUNDLE="build/${APP_NAME}.app"

echo "==> Building (${CONFIG})"
swift build -c "${CONFIG}"

echo "==> Assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Done: ${APP_BUNDLE}"
```

- [ ] **Step 5: Make the script executable and build the bundle**

Run:
```bash
chmod +x scripts/bundle.sh
./scripts/bundle.sh release
```
Expected: ends with `==> Done: build/vClips.app`, no errors.

- [ ] **Step 6: Manual verification — menu bar + capture**

Run:
```bash
open build/vClips.app
```
Verify:
1. A clipboard icon appears in the menu bar; no Dock icon, no window.
2. Copy some text in any app (⌘C), then quit and relaunch the app — open the menu; (history UI lands in Task 4, so for now) confirm the app stays alive and the menu shows "History (⌘⇧V)" and "Quit vClips".
3. Quit via the menu's "Quit vClips".

If the icon does not appear, check Console.app for crash logs and confirm `LSUIElement` is set.

- [ ] **Step 7: Commit**

```bash
git add Sources Resources scripts
git commit -m "feat: menu bar app entry, composition root, and .app bundling"
```

---

## Task 4: Global hotkey + popup panel + searchable list UI

**Files:**
- Create: `Sources/vClips/Hotkey/HotkeyManager.swift`
- Create: `Sources/vClips/UI/PopupViewModel.swift`
- Create: `Sources/vClips/UI/PopupView.swift`
- Create: `Sources/vClips/UI/PopupController.swift`
- Modify: `Sources/vClips/AppEnvironment.swift` (own a `PopupController` + `HotkeyManager`, wire toggle)
- Modify: `Sources/vClips/vClipsApp.swift` (menu "History" button calls `env.togglePopup()`)
- Test: `Tests/vClipsTests/PopupViewModelTests.swift`

**Interfaces:**
- Consumes: `HistoryStore.search(_:)`, `HistoryStore.togglePin(_:)` (Task 1).
- Produces:
  - `final class HotkeyManager` with `init(onTrigger: @escaping () -> Void)`, `func register()`, `func unregister()`. Registers ⌘⇧V (keycode `kVK_ANSI_V`, modifiers `cmdKey | shiftKey`).
  - `@MainActor final class PopupViewModel: ObservableObject` with `@Published var query`, `@Published var selectedIndex`, `@Published private(set) var results: [ClipItem]`, `init(store: HistoryStore, onChoose: @escaping (ClipItem) -> Void)`, `func refresh()`, `func moveSelection(_ delta: Int)`, `func chooseSelected()`, `func togglePinSelected()`.
  - `@MainActor final class PopupController` with `init(rootView:)`, `func toggle()`, `func show()`, `func hide()`.

- [ ] **Step 1: Write the failing tests `Tests/vClipsTests/PopupViewModelTests.swift`**

```swift
import XCTest
import SwiftData
@testable import vClips

@MainActor
final class PopupViewModelTests: XCTestCase {
    private func makeStore() throws -> HistoryStore {
        try HistoryStore(container: ModelContainerFactory.inMemory())
    }

    func test_refresh_loadsAllSortedResults() throws {
        let store = try makeStore()
        store.capture("one")
        store.capture("two")
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.refresh()
        XCTAssertEqual(vm.results.map(\.content), ["two", "one"])
    }

    func test_query_filtersResultsOnRefresh() throws {
        let store = try makeStore()
        store.capture("apple")
        store.capture("banana")
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.query = "app"
        vm.refresh()
        XCTAssertEqual(vm.results.map(\.content), ["apple"])
    }

    func test_moveSelection_clampsWithinBounds() throws {
        let store = try makeStore()
        store.capture("a")
        store.capture("b")
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.refresh()
        XCTAssertEqual(vm.selectedIndex, 0)
        vm.moveSelection(-1)
        XCTAssertEqual(vm.selectedIndex, 0)   // clamped at top
        vm.moveSelection(1)
        XCTAssertEqual(vm.selectedIndex, 1)
        vm.moveSelection(1)
        XCTAssertEqual(vm.selectedIndex, 1)   // clamped at bottom
    }

    func test_chooseSelected_invokesCallbackWithSelectedItem() throws {
        let store = try makeStore()
        store.capture("first")
        store.capture("second")
        var chosen: String?
        let vm = PopupViewModel(store: store, onChoose: { chosen = $0.content })
        vm.refresh()
        vm.moveSelection(1)
        vm.chooseSelected()
        XCTAssertEqual(chosen, "first") // index 1 == older "first"
    }

    func test_togglePinSelected_pinsAndReordersOnRefresh() throws {
        let store = try makeStore()
        store.capture("x")
        store.capture("y")
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.refresh()                 // ["y","x"], selected 0 == "y"
        vm.moveSelection(1)          // select "x"
        vm.togglePinSelected()
        vm.refresh()
        XCTAssertEqual(vm.results.first?.content, "x") // pinned to top
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PopupViewModelTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'PopupViewModel' in scope`.

- [ ] **Step 3: Implement `Sources/vClips/UI/PopupViewModel.swift`**

```swift
import SwiftUI

@MainActor
final class PopupViewModel: ObservableObject {
    @Published var query: String = "" { didSet { refresh() } }
    @Published var selectedIndex: Int = 0
    @Published private(set) var results: [ClipItem] = []

    private let store: HistoryStore
    private let onChoose: (ClipItem) -> Void

    init(store: HistoryStore, onChoose: @escaping (ClipItem) -> Void) {
        self.store = store
        self.onChoose = onChoose
    }

    func refresh() {
        results = store.search(query)
        clampSelection()
    }

    func moveSelection(_ delta: Int) {
        selectedIndex += delta
        clampSelection()
    }

    func chooseSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        onChoose(results[selectedIndex])
    }

    func togglePinSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        store.togglePin(results[selectedIndex])
        refresh()
    }

    private func clampSelection() {
        if results.isEmpty { selectedIndex = 0; return }
        selectedIndex = min(max(selectedIndex, 0), results.count - 1)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PopupViewModelTests 2>&1 | tail -20`
Expected: PASS.

Note: `query`'s `didSet` calls `refresh()`, so the `test_query_filtersResultsOnRefresh` test passes even though it also calls `refresh()` explicitly.

- [ ] **Step 5: Implement `Sources/vClips/UI/PopupView.swift`**

```swift
import SwiftUI

struct PopupView: View {
    @ObservedObject var model: PopupViewModel
    let onEscape: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search clipboard…", text: $model.query)
                .textFieldStyle(.plain)
                .padding(8)
                .focused($searchFocused)
                .onSubmit { model.chooseSelected() }

            Divider()

            ScrollViewReader { proxy in
                List(Array(model.results.enumerated()), id: \.offset) { index, item in
                    HStack {
                        if item.isPinned { Image(systemName: "pin.fill").font(.caption) }
                        Text(item.content)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(index == model.selectedIndex
                                       ? Color.accentColor.opacity(0.25) : Color.clear)
                    .id(index)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectedIndex = index
                        model.chooseSelected()
                    }
                }
                .onChange(of: model.selectedIndex) { _, new in
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
        .frame(width: 380, height: 420)
        .onAppear { searchFocused = true; model.refresh() }
        .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
        .onKeyPress(.return) { model.chooseSelected(); return .handled }
        .onKeyPress(.escape) { onEscape(); return .handled }
        .onKeyPress(keys: ["f"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            model.togglePinSelected(); return .handled
        }
    }
}
```

- [ ] **Step 6: Implement `Sources/vClips/UI/PopupController.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class PopupController {
    private var panel: NSPanel?
    private let makeRootView: () -> AnyView

    init(rootView: @escaping () -> AnyView) {
        self.makeRootView = rootView
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionAtMouse(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: makeRootView())
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
```

- [ ] **Step 7: Implement `Sources/vClips/Hotkey/HotkeyManager.swift`**

```swift
import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyManager {
    private let onTrigger: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x76436c70 // 'vClp'

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    func register() {
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if hkID.id == 1 {
                MainActor.assumeIsolated { manager.onTrigger() }
            }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)

        RegisterEventHotKey(UInt32(kVK_ANSI_V),
                            UInt32(cmdKey | shiftKey),
                            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeyRef = nil
        eventHandler = nil
    }
}
```

- [ ] **Step 8: Wire popup + hotkey into `AppEnvironment.swift`**

Replace the file with:

```swift
import SwiftUI
import SwiftData

@MainActor
final class AppEnvironment: ObservableObject {
    let container: ModelContainer
    let store: HistoryStore
    let monitor: ClipboardMonitor
    private(set) var popup: PopupController!
    private(set) var hotkey: HotkeyManager!
    private(set) var viewModel: PopupViewModel!

    init() {
        let container = try! ModelContainerFactory.onDisk()
        self.container = container
        let store = HistoryStore(container: container)
        self.store = store
        self.monitor = ClipboardMonitor { content in
            store.capture(content)
        }

        self.viewModel = PopupViewModel(store: store, onChoose: { [weak self] item in
            self?.choose(item)
        })
        self.popup = PopupController(rootView: { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(PopupView(model: self.viewModel, onEscape: { self.popup.hide() }))
        })
        self.hotkey = HotkeyManager(onTrigger: { [weak self] in self?.togglePopup() })
    }

    func start() {
        monitor.start()
        hotkey.register()
    }

    func togglePopup() {
        viewModel.query = ""
        viewModel.refresh()
        popup.toggle()
    }

    private func choose(_ item: ClipItem) {
        // Paste behavior wired in Task 5. For now: copy to clipboard + hide.
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.content, forType: .string)
        monitor.markSelfCopy()
        store.markUsed(item)
        popup.hide()
    }
}
```

- [ ] **Step 9: Wire the menu button in `vClipsApp.swift`**

Change the History button action:

```swift
            Button("History (⌘⇧V)") {
                env.togglePopup()
            }
```

- [ ] **Step 10: Build, bundle, run, and verify**

Run:
```bash
swift test 2>&1 | tail -5
./scripts/bundle.sh release && open build/vClips.app
```
Verify manually:
1. Copy several distinct text snippets in another app.
2. Press ⌘⇧V — popup appears near the mouse with the snippets, newest first.
3. Type to filter; list narrows.
4. ↑/↓ moves the highlight; the list scrolls to keep it visible.
5. ⌘F on a row pins it (pin icon, jumps to top).
6. ⏎ or click copies that row's text to the clipboard and closes the popup (paste-into-app comes in Task 5); confirm with ⌘V in a text field.
7. esc closes the popup.

- [ ] **Step 11: Commit**

```bash
git add Sources
git commit -m "feat: global ⌘⇧V hotkey and searchable popup with keyboard navigation"
```

---

## Task 5: Accessibility permission + auto-paste

**Files:**
- Create: `Sources/vClips/Paste/AccessibilityPermission.swift`
- Create: `Sources/vClips/Paste/Paster.swift`
- Modify: `Sources/vClips/AppEnvironment.swift` (route `choose` through `Paster`)
- Modify: `Sources/vClips/vClipsApp.swift` (menu shows permission state + "Grant Accessibility…")

**Interfaces:**
- Consumes: `ClipboardMonitor.markSelfCopy()` (Task 2), `HistoryStore.markUsed(_:)` (Task 1).
- Produces:
  - `enum AccessibilityPermission { static var isTrusted: Bool; static func prompt(); static func openSettings() }`
  - `@MainActor final class Paster` with `init(monitor: ClipboardMonitor)`, `func paste(_ content: String)`. Sets the pasteboard, calls `markSelfCopy()`, and if trusted synthesizes ⌘V via CGEvent; otherwise leaves the text on the clipboard (copy-only fallback).

- [ ] **Step 1: Implement `Sources/vClips/Paste/AccessibilityPermission.swift`**

(No unit test — wraps a system trust check that depends on machine state; verified manually.)

```swift
import ApplicationServices
import AppKit

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt asking the user to grant Accessibility access.
    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: Implement `Sources/vClips/Paste/Paster.swift`**

```swift
import AppKit
import Carbon.HIToolbox
import CoreGraphics

@MainActor
final class Paster {
    private let monitor: ClipboardMonitor

    init(monitor: ClipboardMonitor) {
        self.monitor = monitor
    }

    func paste(_ content: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
        monitor.markSelfCopy()

        guard AccessibilityPermission.isTrusted else {
            return // copy-only fallback; user pastes manually with ⌘V
        }
        synthesizeCommandV()
    }

    private func synthesizeCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 3: Route `choose` through `Paster` in `AppEnvironment.swift`**

Add a `paster` property and update `choose`. In the class, add after `monitor`:

```swift
    private(set) var paster: Paster!
```

In `init()`, after the `monitor` is created, add:

```swift
        self.paster = Paster(monitor: self.monitor)
```

Replace `choose(_:)` with:

```swift
    private func choose(_ item: ClipItem) {
        popup.hide()
        store.markUsed(item)
        paster.paste(item.content)
    }
```

(Order matters: hide the panel first so focus returns to the previous app before ⌘V is synthesized.)

- [ ] **Step 4: Prompt for permission at first launch in `start()`**

In `AppEnvironment.start()`, add after `hotkey.register()`:

```swift
        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.prompt()
        }
```

- [ ] **Step 5: Add permission affordance to the menu in `vClipsApp.swift`**

Add inside the `MenuBarExtra` content, before the Quit divider:

```swift
            if !AccessibilityPermission.isTrusted {
                Divider()
                Button("Grant Accessibility (for auto-paste)…") {
                    AccessibilityPermission.openSettings()
                }
            }
```

- [ ] **Step 6: Build and run tests**

Run:
```bash
swift test 2>&1 | tail -5
swift build 2>&1 | tail -5
```
Expected: tests PASS, `Build complete!`.

- [ ] **Step 7: Bundle and grant permission**

Run:
```bash
./scripts/bundle.sh release && open build/vClips.app
```
Then in System Settings → Privacy & Security → Accessibility, add/enable **vClips** (use the menu's "Grant Accessibility…" to jump there). Because the bundle is ad-hoc signed, after rebuilds you may need to remove and re-add it.

- [ ] **Step 8: Manual verification — auto-paste**

1. With Accessibility granted, focus a text field in another app (e.g. Notes).
2. Press ⌘⇧V, pick an item, press ⏎.
3. Expected: popup closes and the item is typed/pasted directly into the focused field.
4. Revoke Accessibility, repeat: expected fallback — item lands on the clipboard, no auto-paste, and the menu shows "Grant Accessibility…".

- [ ] **Step 9: Commit**

```bash
git add Sources
git commit -m "feat: accessibility permission handling and auto-paste via CGEvent"
```

---

## Task 6: First-run polish & README

**Files:**
- Create: `README.md`
- Modify: `scripts/bundle.sh` (add an `install` step copying to /Applications — optional convenience)

**Interfaces:** none (documentation + convenience).

- [ ] **Step 1: Write `README.md`**

```markdown
# vClips

A macOS-native menu-bar clipboard manager: text history, search, and pinned favorites,
summoned anywhere with ⌘⇧V and auto-pasted into the focused app.

## Requirements
- macOS 14+
- Full Xcode (SwiftData macros are not in Command Line Tools)

## Build & run
```bash
./scripts/bundle.sh release
open build/vClips.app
```

## First run
1. Grant Accessibility access when prompted (enables auto-paste). Without it, vClips
   falls back to copy-only — selected items go to the clipboard for manual ⌘V.

## Usage
- **⌘⇧V** — open the history popup (near the mouse)
- **type** — filter; **↑/↓** — move; **⏎** — paste; **⌘F** — pin/unpin; **esc** — close
- Menu-bar icon → History / Quit

## Privacy
All history is stored locally via SwiftData. Items marked concealed/transient
(e.g. password managers) are never captured. No network access.

## Defaults
Polling 0.5s · max 200 unpinned items · hotkey ⌘⇧V · text only.
```

- [ ] **Step 2: Add an optional install step to `scripts/bundle.sh`**

Append:

```bash
if [[ "${2:-}" == "install" ]]; then
  echo "==> Installing to /Applications"
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "${APP_BUNDLE}" "/Applications/${APP_NAME}.app"
  echo "==> Installed: /Applications/${APP_NAME}.app"
fi
```

- [ ] **Step 3: Verify the install path**

Run: `./scripts/bundle.sh release install && ls -d /Applications/vClips.app`
Expected: prints the installed path.

- [ ] **Step 4: Commit**

```bash
git add README.md scripts
git commit -m "docs: add README and optional install step"
```

---

## Self-Review Notes

- **Spec coverage:** menu-bar app + LSUIElement (Task 3); text history/dedup/cleanup/pin (Task 1); search (Tasks 1, 4); concealed/transient privacy filter (Task 2); polling + loop prevention (Task 2); global ⌘⇧V + nonactivating panel (Task 4); auto-paste + Accessibility fallback (Task 5); SwiftData persistence (Task 1); defaults 0.5s/200/⌘⇧V/text-only (Global Constraints, Tasks 1–2). Xcode/SwiftData environment gap addressed by Task 0.
- **Type consistency:** `capture`, `search`, `togglePin`, `markUsed`, `markSelfCopy`, `paste`, `togglePopup`, `refresh`, `moveSelection`, `chooseSelected`, `togglePinSelected` referenced consistently across tasks.
- **Known manual-only areas:** `ClipboardMonitor`, `HotkeyManager`, `PopupController`, `Paster`, `AccessibilityPermission` are system-integration units verified by the manual steps in Tasks 3–5 rather than unit tests; pure logic (`HistoryStore`, `PasteboardPolicy`, `PopupViewModel`) is unit-tested.
- **Risk:** the `scenePhaseProxy` launch seam in `vClipsApp` (Task 3) is intentionally simple; if `env.start()` is observed running more than once, convert to an `NSApplicationDelegateAdaptor` with `applicationDidFinishLaunching`.
```
