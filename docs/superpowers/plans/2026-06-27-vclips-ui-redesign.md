# vClips UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the clipboard popup as a translucent-glass macOS UI with separate Favorites/Recent sections, smart type icons, hover actions (★ favorite, × delete), per-item delete, and a preview pane for long items.

**Architecture:** Keep the existing component split. Add a pure `ContentType` helper and a `HistoryStore.delete`, refactor `PopupViewModel` to expose `favorites`/`recents`/`results` (flat selection list) and `deleteSelected()`, wrap the panel content in an `NSVisualEffectView` for vibrancy, and rewrite `PopupView` with sectioned rows, hover controls, selection pill, and a preview pane.

**Tech Stack:** Swift 6 (SwiftUI, SwiftData, AppKit). Build via SwiftPM + `scripts/bundle.sh` (signs with the stable "vClips Self Signed" identity).

## Global Constraints

- **No new dependencies.** Only the existing `KeyboardShortcuts` package; add no others.
- **Min deployment target macOS 14.** Text content only (`.string`); no image/file thumbnails.
- **Popup width 380pt**, height variable (~460pt with preview).
- **Sections:** "FAVORITES" (pinned, shown only when non-empty) then "RECENT" (unpinned); when a search query is present, show a single list (pinned first) with no section headers.
- **Sort:** pinned first, then `lastUsedAt` descending (unchanged from `HistoryStore.search`).
- **Item-delete keyboard shortcut is ⌘⌫** (command+delete), NOT bare ⌫ — the search field is always focused, so a bare ⌫ must edit the query text. The hover × button is the mouse affordance.
- **Build & sign for manual checks:** `./scripts/bundle.sh release install` then run `/Applications/vClips.app`. Do not revert to ad-hoc signing.
- **Preserve existing behavior:** auto-paste flow, the accessory-app activation/`didBecomeKey` focus handling, and loop prevention must keep working.
- **Commit after every task.**

---

## File Structure

```
Sources/vClips/UI/ContentType.swift     # NEW: pure content-kind detection + SF Symbol name
Sources/vClips/Store/HistoryStore.swift # MODIFY: add delete(_:)
Sources/vClips/UI/PopupViewModel.swift  # MODIFY: favorites/recents/results split + deleteSelected()
Sources/vClips/UI/PopupController.swift  # MODIFY: NSVisualEffectView glass background
Sources/vClips/UI/PopupView.swift        # REWRITE: sections, RowView (icons + hover ★/×), pill, preview, ⌘⌫
Tests/vClipsTests/ContentTypeTests.swift     # NEW
Tests/vClipsTests/HistoryStoreDeleteTests.swift  # NEW
Tests/vClipsTests/PopupViewModelTests.swift  # MODIFY: add favorites/recents/delete tests
```

---

## Task 1: ContentType detection (pure helper)

**Files:**
- Create: `Sources/vClips/UI/ContentType.swift`
- Test: `Tests/vClipsTests/ContentTypeTests.swift`

**Interfaces:**
- Produces: `enum ContentType { case url, email, filePath, text }` with `static func detect(_ text: String) -> ContentType` and `var symbolName: String`. Consumed by `PopupView` (Task 5).

- [ ] **Step 1: Write the failing test `Tests/vClipsTests/ContentTypeTests.swift`**

```swift
import XCTest
@testable import vClips

final class ContentTypeTests: XCTestCase {
    func test_detectsURL() {
        XCTAssertEqual(ContentType.detect("https://example.com"), .url)
        XCTAssertEqual(ContentType.detect("http://a.b/c?d=e"), .url)
    }

    func test_detectsURL_trimsWhitespace() {
        XCTAssertEqual(ContentType.detect("  https://example.com \n"), .url)
    }

    func test_detectsEmail() {
        XCTAssertEqual(ContentType.detect("john@example.com"), .email)
    }

    func test_detectsFilePath() {
        XCTAssertEqual(ContentType.detect("/Users/bible/file.txt"), .filePath)
        XCTAssertEqual(ContentType.detect("~/Documents/notes.md"), .filePath)
    }

    func test_plainTextFallback() {
        XCTAssertEqual(ContentType.detect("hello world"), .text)
        XCTAssertEqual(ContentType.detect("not@an@email"), .text)
    }

    func test_symbolNames() {
        XCTAssertEqual(ContentType.url.symbolName, "link")
        XCTAssertEqual(ContentType.email.symbolName, "envelope")
        XCTAssertEqual(ContentType.filePath.symbolName, "doc")
        XCTAssertEqual(ContentType.text.symbolName, "doc.on.clipboard")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ContentTypeTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'ContentType' in scope`.

- [ ] **Step 3: Create `Sources/vClips/UI/ContentType.swift`**

```swift
import Foundation

enum ContentType {
    case url
    case email
    case filePath
    case text

    static func detect(_ text: String) -> ContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if matchesEmail(trimmed) { return .email }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return .url }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") { return .filePath }
        return .text
    }

    var symbolName: String {
        switch self {
        case .url: return "link"
        case .email: return "envelope"
        case .filePath: return "doc"
        case .text: return "doc.on.clipboard"
        }
    }

    private static func matchesEmail(_ s: String) -> Bool {
        guard !s.contains(" "), !s.contains("\n") else { return false }
        let pattern = "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"
        return s.range(of: pattern, options: .regularExpression) != nil
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter ContentTypeTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/vClips/UI/ContentType.swift Tests/vClipsTests/ContentTypeTests.swift
git commit -m "feat: add ContentType detection for smart row icons"
```

---

## Task 2: HistoryStore.delete

**Files:**
- Modify: `Sources/vClips/Store/HistoryStore.swift`
- Test: `Tests/vClipsTests/HistoryStoreDeleteTests.swift`

**Interfaces:**
- Consumes: existing `HistoryStore(container:)`, `capture(_:)`, `search(_:)`, `togglePin(_:)`.
- Produces: `func delete(_ item: ClipItem)` on `HistoryStore`. Consumed by `PopupViewModel` (Task 3).

- [ ] **Step 1: Write the failing test `Tests/vClipsTests/HistoryStoreDeleteTests.swift`**

```swift
import XCTest
import SwiftData
@testable import vClips

@MainActor
final class HistoryStoreDeleteTests: XCTestCase {
    private func makeStore() throws -> HistoryStore {
        try HistoryStore(container: ModelContainerFactory.inMemory())
    }

    func test_delete_removesUnpinnedItem() throws {
        let store = try makeStore()
        store.capture("a")
        store.capture("b")
        let b = store.search("").first { $0.content == "b" }!
        store.delete(b)
        XCTAssertEqual(store.search("").map(\.content), ["a"])
    }

    func test_delete_removesPinnedItem() throws {
        let store = try makeStore()
        store.capture("keep")
        let item = store.search("").first!
        store.togglePin(item)
        store.delete(item)
        XCTAssertTrue(store.search("").isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter HistoryStoreDeleteTests 2>&1 | tail -20`
Expected: FAIL — `value of type 'HistoryStore' has no member 'delete'`.

- [ ] **Step 3: Add `delete(_:)` to `Sources/vClips/Store/HistoryStore.swift`**

Insert this method right after `markUsed(_:)` (after line 50, before `firstItem`):

```swift
    func delete(_ item: ClipItem) {
        context.delete(item)
        save()
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter HistoryStoreDeleteTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/vClips/Store/HistoryStore.swift Tests/vClipsTests/HistoryStoreDeleteTests.swift
git commit -m "feat: add HistoryStore.delete for per-item removal"
```

---

## Task 3: PopupViewModel — sections + deleteSelected

**Files:**
- Modify: `Sources/vClips/UI/PopupViewModel.swift`
- Modify: `Tests/vClipsTests/PopupViewModelTests.swift`

**Interfaces:**
- Consumes: `HistoryStore.search(_:)`, `togglePin(_:)`, `delete(_:)` (Task 2).
- Produces on `PopupViewModel`: `@Published private(set) var favorites: [ClipItem]`, `@Published private(set) var recents: [ClipItem]`, `@Published private(set) var results: [ClipItem]` (flat = favorites + recents; `selectedIndex` indexes this), `func deleteSelected()`. Existing `query`, `refresh()`, `moveSelection(_:)`, `chooseSelected()`, `togglePinSelected()`, `selectedIndex` remain. Consumed by `PopupView` (Task 5).

- [ ] **Step 1: Replace `Sources/vClips/UI/PopupViewModel.swift`**

```swift
import SwiftUI

@MainActor
final class PopupViewModel: ObservableObject {
    @Published var query: String = "" { didSet { refresh() } }
    @Published var selectedIndex: Int = 0
    /// Pinned items, shown under the FAVORITES header (empty while searching).
    @Published private(set) var favorites: [ClipItem] = []
    /// Unpinned items (or, while searching, the full matching list, pinned first).
    @Published private(set) var recents: [ClipItem] = []
    /// Flat display order (favorites + recents); `selectedIndex` indexes this.
    @Published private(set) var results: [ClipItem] = []

    private let store: HistoryStore
    private let onChoose: (ClipItem) -> Void

    init(store: HistoryStore, onChoose: @escaping (ClipItem) -> Void) {
        self.store = store
        self.onChoose = onChoose
    }

    func refresh() {
        let all = store.search(query)
        if query.isEmpty {
            favorites = all.filter { $0.isPinned }
            recents = all.filter { !$0.isPinned }
        } else {
            // While searching, present a single list (already pinned-first sorted).
            favorites = []
            recents = all
        }
        results = favorites + recents
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

    func deleteSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        store.delete(results[selectedIndex])
        refresh()
    }

    private func clampSelection() {
        if results.isEmpty { selectedIndex = 0; return }
        selectedIndex = min(max(selectedIndex, 0), results.count - 1)
    }
}
```

- [ ] **Step 2: Add tests to `Tests/vClipsTests/PopupViewModelTests.swift`**

Append these methods inside the existing `PopupViewModelTests` class (before its closing brace). They reuse the existing `makeStore()` helper in that file.

```swift
    func test_refresh_splitsFavoritesAndRecents() throws {
        let store = try makeStore()
        store.capture("plain")
        store.capture("fav")
        let fav = store.search("").first { $0.content == "fav" }!
        store.togglePin(fav)
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.refresh()
        XCTAssertEqual(vm.favorites.map(\.content), ["fav"])
        XCTAssertEqual(vm.recents.map(\.content), ["plain"])
        XCTAssertEqual(vm.results.map(\.content), ["fav", "plain"]) // favorites first
    }

    func test_refresh_whileSearching_isSingleListNoFavoritesSection() throws {
        let store = try makeStore()
        store.capture("apple")
        store.capture("apricot")
        let apple = store.search("").first { $0.content == "apple" }!
        store.togglePin(apple)
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.query = "ap"
        vm.refresh()
        XCTAssertTrue(vm.favorites.isEmpty)
        XCTAssertEqual(vm.recents.map(\.content), ["apple", "apricot"]) // pinned first
        XCTAssertEqual(vm.results.count, 2)
    }

    func test_deleteSelected_removesItemAndClampsSelection() throws {
        let store = try makeStore()
        store.capture("one")
        store.capture("two") // results: ["two","one"], selected 0
        let vm = PopupViewModel(store: store, onChoose: { _ in })
        vm.refresh()
        vm.moveSelection(1) // select index 1 == "one"
        vm.deleteSelected()
        XCTAssertEqual(vm.results.map(\.content), ["two"])
        XCTAssertEqual(vm.selectedIndex, 0) // clamped from 1 to last valid
    }
```

- [ ] **Step 3: Run the tests to verify the new ones pass and old ones still pass**

Run: `swift test --filter PopupViewModelTests 2>&1 | tail -20`
Expected: PASS (existing 5 + new 3 = 8 tests in this class). The existing tests reference `vm.results` which is unchanged in meaning (flat display list).

- [ ] **Step 4: Confirm the whole suite builds (PopupView still compiles against `results`)**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!` — the current `PopupView` uses `model.results`, which still exists.

- [ ] **Step 5: Commit**

```bash
git add Sources/vClips/UI/PopupViewModel.swift Tests/vClipsTests/PopupViewModelTests.swift
git commit -m "feat: PopupViewModel favorites/recents split and deleteSelected"
```

---

## Task 4: Glass (vibrancy) panel background

**Files:**
- Modify: `Sources/vClips/UI/PopupController.swift`

**Interfaces:**
- Consumes: existing `PopupController(rootView:)`, `makePanel()`.
- Produces: no API change; the panel now renders on an `NSVisualEffectView` with rounded corners.

- [ ] **Step 1: Update `makePanel()` in `Sources/vClips/UI/PopupController.swift`**

Replace the body of `makePanel()` (the method starting `private func makePanel() -> NSPanel {`) with this version. It keeps the `KeyablePanel` type, panel flags, and positioning unchanged, and only swaps the content view for a vibrancy-backed host.

```swift
    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
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
        panel.isOpaque = false
        panel.backgroundColor = .clear

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true

        let host = NSHostingView(rootView: makeRootView())
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        panel.contentView = effect
        return panel
    }
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!` (note any warnings).

- [ ] **Step 3: Manual verification — glass background**

Run:
```bash
pkill -x vClips 2>/dev/null; sleep 1
./scripts/bundle.sh release install
open /Applications/vClips.app
```
Press ⌘⇧V. Expected: the popup now has a translucent, blurred (vibrancy) background with rounded corners; content (search field + list) is readable on top. Keyboard/typing/selection still work (the panel is still a `KeyablePanel` and focus handling is unchanged). Quit with `pkill -x vClips`.

- [ ] **Step 4: Commit**

```bash
git add Sources/vClips/UI/PopupController.swift
git commit -m "feat: translucent glass (vibrancy) popup background"
```

---

## Task 5: PopupView rewrite — sections, rows, hover actions, preview

**Files:**
- Modify (rewrite): `Sources/vClips/UI/PopupView.swift`

**Interfaces:**
- Consumes: `PopupViewModel` (`favorites`, `recents`, `results`, `selectedIndex`, `query`, `refresh()`, `moveSelection(_:)`, `chooseSelected()`, `togglePinSelected()`, `deleteSelected()`); `ContentType.detect(_:)` / `symbolName`; `ClipItem` (`content`, `isPinned`).
- Produces: the redesigned popup view. No API consumed by others.

- [ ] **Step 1: Rewrite `Sources/vClips/UI/PopupView.swift`**

```swift
import SwiftUI
import AppKit

struct PopupView: View {
    @ObservedObject var model: PopupViewModel
    let onEscape: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().opacity(0.5)
            if model.results.isEmpty {
                emptyState
            } else {
                listBody
            }
            if let preview = previewText {
                Divider().opacity(0.5)
                previewPane(preview)
            }
        }
        .frame(width: 380)
        .frame(minHeight: 200, maxHeight: 460)
        .onAppear { searchFocused = true }
        // First popup after launch becomes key asynchronously; re-assert focus then.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            searchFocused = true
        }
        .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
        .onKeyPress(.return) { model.chooseSelected(); return .handled }
        .onKeyPress(.escape) { onEscape(); return .handled }
        .onKeyPress(keys: ["f"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            model.togglePinSelected(); return .handled
        }
        // ⌘⌫ deletes the selected item. Bare ⌫ is left for editing the search field.
        .onKeyPress(.delete) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            model.deleteSelected(); return .handled
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clipboard…", text: $model.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { model.chooseSelected() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var listBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !model.favorites.isEmpty {
                        sectionHeader("FAVORITES")
                        ForEach(Array(model.favorites.enumerated()), id: \.element.persistentModelID) { offset, item in
                            row(item, flatIndex: offset)
                        }
                    }
                    if !model.recents.isEmpty {
                        if !model.favorites.isEmpty || model.query.isEmpty {
                            sectionHeader(model.query.isEmpty ? "RECENT" : "RESULTS")
                        }
                        ForEach(Array(model.recents.enumerated()), id: \.element.persistentModelID) { offset, item in
                            row(item, flatIndex: model.favorites.count + offset)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .onChange(of: model.selectedIndex) { _, new in
                proxy.scrollTo(new, anchor: .center)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: ClipItem, flatIndex: Int) -> some View {
        RowView(
            item: item,
            isSelected: flatIndex == model.selectedIndex,
            onTap: { model.selectedIndex = flatIndex; model.chooseSelected() },
            onTogglePin: { model.selectedIndex = flatIndex; model.togglePinSelected() },
            onDelete: { model.selectedIndex = flatIndex; model.deleteSelected() }
        )
        .id(flatIndex)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text(model.query.isEmpty ? "No clipboard history yet" : "No matches")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var previewText: String? {
        guard model.results.indices.contains(model.selectedIndex) else { return nil }
        let content = model.results[model.selectedIndex].content
        let isLong = content.count > 60 || content.contains("\n")
        return isLong ? content : nil
    }

    private func previewPane(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: 90)
    }
}

private struct RowView: View {
    let item: ClipItem
    let isSelected: Bool
    let onTap: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ContentType.detect(item.content).symbolName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(item.content.replacingOccurrences(of: "\n", with: " "))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if isSelected || hovering {
                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "star.fill" : "star")
                        .foregroundStyle(item.isPinned ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unfavorite (⌘F)" : "Favorite (⌘F)")

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete (⌘⌫)")
            } else if item.isPinned {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.30) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
    }
}
```

- [ ] **Step 2: Build and run the suite**

Run: `swift build 2>&1 | tail -3 && swift test 2>&1 | grep -iE "Executed [0-9]+ tests|failure" | tail -2`
Expected: `Build complete!` and the suite passes (now includes ContentType + delete + viewModel tests).

- [ ] **Step 3: Manual verification — full redesigned popup**

Run:
```bash
pkill -x vClips 2>/dev/null; sleep 1
./scripts/bundle.sh release install
open /Applications/vClips.app
```
Copy a few varied items (a URL, an email, a file path, a long multi-line paragraph), then ⌘⇧V and verify:
1. Glass background; search field with magnifier; rows show type icons (link/envelope/doc/clipboard).
2. ⌘F (or hover ★) favorites an item → it moves under a "FAVORITES" header at top with a filled star.
3. Hover a row → ★ and × buttons appear on the right; clicking × deletes that row; ⌘⌫ deletes the selected row.
4. Selecting a long/multi-line item shows a preview pane at the bottom; short items show no preview.
5. Typing filters to a single list (no section headers); ↑↓ move the rounded-pill selection; ⏎ pastes; esc closes.
6. Empty history (or no matches) shows the placeholder text.

- [ ] **Step 4: Commit**

```bash
git add Sources/vClips/UI/PopupView.swift
git commit -m "feat: redesigned popup — sections, type icons, hover actions, preview"
```

---

## Self-Review Notes

- **Spec coverage:** glass vibrancy (Task 4); Favorites/Recent sections + headers (Task 3 split + Task 5 headers); smart type icons (Task 1 + Task 5 rows); hover ★/× actions (Task 5 RowView); per-item delete via × and ⌘⌫ + `HistoryStore.delete` (Tasks 2, 3, 5); long-text preview pane (Task 5); selection pill (Task 5); search = single list, pinned first (Task 3); empty/no-favorites/searching/after-delete edge cases (Task 3 + Task 5 empty state, conditional headers, clamp); width 380 (Task 5); no new deps / macOS 14 / text-only (Global Constraints). All spec sections map to a task.
- **Spec deviation (documented):** item-delete key is ⌘⌫ not bare ⌫ (the always-focused search field needs ⌫ for text editing); the spec's intent (keyboard delete + hover ×) is preserved. Called out in Global Constraints and Task 5.
- **Placeholder scan:** none — all code/commands concrete.
- **Type consistency:** `ContentType.detect`/`symbolName`, `HistoryStore.delete`, `PopupViewModel.favorites/recents/results/selectedIndex/deleteSelected/togglePinSelected/chooseSelected/moveSelection`, and `RowView(item:isSelected:onTap:onTogglePin:onDelete:)` are used consistently across tasks. `PopupView` keeps consuming `model.results` so the build stays green between Tasks 3 and 5.
- **Risk:** `ForEach` keyed on `\.element.persistentModelID` assumes `ClipItem` (a SwiftData `@Model`) exposes `persistentModelID` — it does, for all `PersistentModel`. If list-row identity ever misbehaves, fall back to keying on `\.element.content`. The `.onKeyPress(.delete)` requires the container to receive the event; since the search field is focused, the modifier-guarded handler (⌘⌫) is what makes it reach this handler rather than the text field.
