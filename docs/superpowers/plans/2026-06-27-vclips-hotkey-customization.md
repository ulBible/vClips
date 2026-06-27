# vClips Hotkey Customization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user change the global "open clipboard popup" hotkey from a Settings window using a record-style recorder, persisted automatically, defaulting to the current ⌘⇧V.

**Architecture:** Replace the hand-rolled Carbon `HotkeyManager` with the `KeyboardShortcuts` SwiftPM package, which provides the recorder UI, `UserDefaults` persistence, and global registration. A SwiftUI `Settings` scene hosts the recorder; `AppEnvironment` registers a key-down handler that calls the existing `togglePopup()`.

**Tech Stack:** Swift 6 (SwiftUI, SwiftData, AppKit), KeyboardShortcuts (sindresorhus, MIT). Build via SwiftPM + the existing `scripts/bundle.sh` (now signs with the stable self-signed identity).

## Global Constraints

- **New dependency (this feature only):** `KeyboardShortcuts` from `https://github.com/sindresorhus/KeyboardShortcuts`, `from: "2.0.0"`, product name `KeyboardShortcuts`. This is the ONLY external dependency; do not add others. **The first build fetches it over the network** — if the environment blocks network access during `swift build`, stop and report (the rest of the plan cannot build).
- **Minimum deployment target:** macOS 14. No change.
- **Shortcut name + default:** exactly one shortcut, `KeyboardShortcuts.Name.togglePopup`, default `KeyboardShortcuts.Shortcut(.v, modifiers: [.command, .shift])` (⌘⇧V) — preserves existing behavior, no migration.
- **Persistence:** `KeyboardShortcuts` stores in `UserDefaults` (com.vclips.app domain) automatically. Do NOT add SwiftData for this.
- **Build & sign for manual checks:** `./scripts/bundle.sh release install` then run `/Applications/vClips.app`. The stable "vClips Self Signed" identity keeps the Accessibility grant; do not revert to ad-hoc.
- **Menu-bar-only app** (LSUIElement) is unchanged.
- **Commit after every task.**

---

## File Structure

```
Package.swift                          # add KeyboardShortcuts dependency to both targets
Sources/vClips/Hotkey/
    Shortcuts.swift                    # NEW: KeyboardShortcuts.Name.togglePopup (+ default ⌘⇧V)
    HotkeyManager.swift                # DELETED: replaced by KeyboardShortcuts
Sources/vClips/AppEnvironment.swift    # MODIFY: drop HotkeyManager, register KeyboardShortcuts handler
Sources/vClips/UI/SettingsView.swift   # NEW: recorder UI
Sources/vClips/vClipsApp.swift         # MODIFY: add Settings scene + "Settings…" menu item; fix menu label
Tests/vClipsTests/ShortcutsTests.swift # NEW: assert the default shortcut is ⌘⇧V
```

---

## Task 1: Add KeyboardShortcuts dependency and define the shortcut name

**Files:**
- Modify: `Package.swift`
- Create: `Sources/vClips/Hotkey/Shortcuts.swift`
- Test: `Tests/vClipsTests/ShortcutsTests.swift`

**Interfaces:**
- Produces: `KeyboardShortcuts.Name.togglePopup` (a `KeyboardShortcuts.Name`) with `defaultShortcut == KeyboardShortcuts.Shortcut(.v, modifiers: [.command, .shift])`. Consumed by Tasks 2 and 3.

- [ ] **Step 1: Replace `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vClips",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "vClips",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/vClips"
        ),
        .testTarget(
            name: "vClipsTests",
            dependencies: [
                "vClips",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Tests/vClipsTests"
        ),
    ]
)
```

- [ ] **Step 2: Resolve the dependency (fetches over network)**

Run: `swift package resolve 2>&1 | tail -10`
Expected: resolves `KeyboardShortcuts` (a version ≥ 2.0.0), no error. If it fails with a network error, STOP and report — the environment blocks dependency fetching.

- [ ] **Step 3: Write the failing test `Tests/vClipsTests/ShortcutsTests.swift`**

```swift
import XCTest
import KeyboardShortcuts
@testable import vClips

final class ShortcutsTests: XCTestCase {
    func test_togglePopup_defaultIsCommandShiftV() {
        XCTAssertEqual(
            KeyboardShortcuts.Name.togglePopup.defaultShortcut,
            KeyboardShortcuts.Shortcut(.v, modifiers: [.command, .shift])
        )
    }
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `swift test --filter ShortcutsTests 2>&1 | tail -20`
Expected: FAIL — compile error `type 'KeyboardShortcuts.Name' has no member 'togglePopup'` (not yet defined).

- [ ] **Step 5: Create `Sources/vClips/Hotkey/Shortcuts.swift`**

```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global hotkey that opens the clipboard history popup. Defaults to ⌘⇧V,
    /// matching the original fixed shortcut. User changes are stored in
    /// UserDefaults by KeyboardShortcuts automatically.
    static let togglePopup = Self("togglePopup", default: .init(.v, modifiers: [.command, .shift]))
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `swift test --filter ShortcutsTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 7: Confirm the whole suite still builds and passes**

Run: `swift test 2>&1 | grep -iE "Executed [0-9]+ tests|failure" | tail -3`
Expected: `Executed 18 tests, with 0 failures` (17 existing + 1 new).

- [ ] **Step 8: Commit**

```bash
git add Package.swift Package.resolved Sources/vClips/Hotkey/Shortcuts.swift Tests/vClipsTests/ShortcutsTests.swift
git commit -m "feat: add KeyboardShortcuts dependency and togglePopup shortcut (default ⌘⇧V)"
```

---

## Task 2: Drive the popup from KeyboardShortcuts; remove HotkeyManager

**Files:**
- Modify: `Sources/vClips/AppEnvironment.swift`
- Delete: `Sources/vClips/Hotkey/HotkeyManager.swift`

**Interfaces:**
- Consumes: `KeyboardShortcuts.Name.togglePopup` (Task 1); existing `AppEnvironment.togglePopup()`.
- Produces: `AppEnvironment` no longer exposes `hotkey`; the global shortcut is registered in `start()`.

- [ ] **Step 1: Replace `Sources/vClips/AppEnvironment.swift`**

```swift
import SwiftUI
import SwiftData
import KeyboardShortcuts

@MainActor
final class AppEnvironment: ObservableObject {
    let container: ModelContainer
    let store: HistoryStore
    let monitor: ClipboardMonitor
    private(set) var paster: Paster!
    private(set) var popup: PopupController!
    private(set) var viewModel: PopupViewModel!

    init() {
        let container = try! ModelContainerFactory.onDisk()
        self.container = container
        let store = HistoryStore(container: container)
        self.store = store
        self.monitor = ClipboardMonitor { content in
            store.capture(content)
        }
        self.paster = Paster(monitor: self.monitor)

        self.viewModel = PopupViewModel(store: store, onChoose: { [weak self] item in
            self?.choose(item)
        })
        self.popup = PopupController(rootView: { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(PopupView(model: self.viewModel, onEscape: { self.popup.hide() }))
        })
    }

    func start() {
        monitor.start()
        KeyboardShortcuts.onKeyDown(for: .togglePopup) { [weak self] in
            self?.togglePopup()
        }
        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.prompt()
        }
    }

    func togglePopup() {
        viewModel.query = ""
        viewModel.refresh()
        popup.toggle()
    }

    private func choose(_ item: ClipItem) {
        popup.hide()
        store.markUsed(item)
        paster.paste(item.content)
    }
}
```

- [ ] **Step 2: Delete the old hotkey manager**

Run: `git rm Sources/vClips/Hotkey/HotkeyManager.swift`
Expected: file removed. (Nothing else references it — only `AppEnvironment` did.)

- [ ] **Step 3: Confirm no dangling references**

Run: `grep -rn "HotkeyManager" Sources Tests`
Expected: no output (all references gone).

- [ ] **Step 4: Build and run the suite**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | grep -iE "Executed [0-9]+ tests|failure" | tail -2`
Expected: `Build complete!` and `Executed 18 tests, with 0 failures`.

- [ ] **Step 5: Manual verification — default shortcut still opens the popup**

Run:
```bash
pkill -x vClips 2>/dev/null; sleep 1
./scripts/bundle.sh release install
open /Applications/vClips.app
```
Then: copy some text, press **⌘⇧V**. Expected: the popup appears as before (now driven by KeyboardShortcuts). Pick an item and confirm paste still works. Quit when done (`pkill -x vClips`).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: register global popup hotkey via KeyboardShortcuts; remove Carbon HotkeyManager"
```

---

## Task 3: Settings window with the recorder + menu entry

**Files:**
- Create: `Sources/vClips/UI/SettingsView.swift`
- Modify: `Sources/vClips/vClipsApp.swift`

**Interfaces:**
- Consumes: `KeyboardShortcuts.Name.togglePopup` (Task 1).
- Produces: a `Settings` scene and a menu item that opens it. No code consumes these later.

- [ ] **Step 1: Create `Sources/vClips/UI/SettingsView.swift`**

```swift
import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Open clipboard popup:", name: .togglePopup)
        }
        .padding(20)
        .frame(width: 360)
    }
}
```

- [ ] **Step 2: Replace `Sources/vClips/vClipsApp.swift`**

```swift
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let env = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        env.start()
    }
}

@main
struct vClipsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("vClips", systemImage: "doc.on.clipboard") {
            Button("History") {
                appDelegate.env.togglePopup()
            }
            SettingsLink {
                Text("Settings…")
            }
            if !AccessibilityPermission.isTrusted {
                Divider()
                Button("Grant Accessibility (for auto-paste)…") {
                    AccessibilityPermission.openSettings()
                }
            }
            Divider()
            Button("Quit vClips") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}
```

Note: the menu label changed from `"History (⌘⇧V)"` to `"History"` because the shortcut is now user-configurable, so the hard-coded combo would be misleading. `SettingsLink` (macOS 14+) opens the `Settings` scene and handles app activation from a menu-bar (accessory) app.

- [ ] **Step 3: Build and run the suite**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | grep -iE "Executed [0-9]+ tests|failure" | tail -2`
Expected: `Build complete!` and `Executed 18 tests, with 0 failures`.

- [ ] **Step 4: Manual verification — change the shortcut and confirm it works live**

Run:
```bash
pkill -x vClips 2>/dev/null; sleep 1
./scripts/bundle.sh release install
open /Applications/vClips.app
```
Then verify:
1. Menu-bar icon → **Settings…** opens a small window with a recorder labeled "Open clipboard popup:" showing the current shortcut (⌘⇧V).
2. Click the recorder, press a new combo (e.g. **⌃⌥V**). The recorder shows the new combo.
3. The **new** shortcut opens the popup; the **old** ⌘⇧V no longer does.
4. Clear the recorder (the ⌫/clear control) → no shortcut opens the popup; the menu-bar **History** item still does.
5. Quit and relaunch (`pkill -x vClips; open /Applications/vClips.app`); the chosen shortcut persists.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: Settings window with shortcut recorder and menu entry"
```

---

## Self-Review Notes

- **Spec coverage:** recorder input (Task 3 `KeyboardShortcuts.Recorder`); KeyboardShortcuts library + replaces HotkeyManager (Tasks 1–2); UserDefaults persistence (library default, Global Constraints); default ⌘⇧V / no migration (Task 1 + test); live re-registration & old-shortcut release (library, verified Task 3 Step 4.3); empty value disables shortcut (verified Task 3 Step 4.4); Settings opened from menu (Task 3 `SettingsLink`); start() registers handler (Task 2). All spec sections map to a task.
- **Placeholder scan:** none — all code and commands are concrete.
- **Type consistency:** `KeyboardShortcuts.Name.togglePopup`, `KeyboardShortcuts.Shortcut(.v, modifiers: [.command, .shift])`, `KeyboardShortcuts.onKeyDown(for:)`, `KeyboardShortcuts.Recorder(_:name:)`, and `AppEnvironment.togglePopup()` are used consistently across tasks.
- **Risk:** if `KeyboardShortcuts.Name.defaultShortcut` differs by library version, Task 1 Step 3's assertion may need the version-appropriate accessor; the recorder/handler/`Shortcut` API used here is stable across 2.x. If `SettingsLink` fails to open the window from the accessory app, fall back to a `Button` that calls the standard show-settings action — but try `SettingsLink` first.
