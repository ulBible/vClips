# MAS 카피 전용 빌드 (1.2.5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** vClipsAppStore 빌드에서 Accessibility 의존을 완전히 제거하고(카피 전용), 복사 후 "⌘V to paste" 토스트로 UX를 보강한다. 직배포 빌드는 자동 붙여넣기 유지.

**Architecture:** 런타임 플래그 `autoPasteCapable`을 엔트리포인트에서 `AppEnvironment`로 주입 (기존 `showsSupportLink` 패턴). `Paster`는 플래그가 꺼지면 AX 검사·CGEvent 합성·AutoPasteOffer에 도달하지 않는다. 새 `CopyToast`는 합성 없이 복사만 한 모든 경우에 뜨는 non-activating HUD.

**Tech Stack:** Swift 6 / SwiftUI + AppKit / SwiftPM 멀티타깃 (vClipsCore 공유, vClips·vClipsAppStore 엔트리) / XCTest (`Tests/vClipsTests`, `@testable import vClipsCore`)

## Global Constraints

- 스펙: `docs/superpowers/specs/2026-08-12-mas-copy-only-design.md`
- MAS 빌드에서 AX API 호출·권한 프롬프트·"Accessibility/auto-paste" 문구가 **어떤 경로로도** 발생하지 않아야 한다. 단락 평가(`autoPasteCapable && …`)로 AX 호출 자체를 차단한다.
- 토스트 문구는 정확히 `Copied — press ⌘V to paste`. 설정 키는 `showCopyToast`, 기본 `true`.
- 앱 내에 직배포판 언급 금지.
- 커밋 메시지 끝에 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- 빌드 확인은 `swift build` (양 product 포함), 테스트는 `swift test`.

---

### Task 1: Paster 결정 로직 (순수 함수) + 플래그 저장

**Files:**
- Modify: `Sources/vClipsCore/Paste/Paster.swift`
- Test: `Tests/vClipsTests/PasterActionTests.swift` (create)

**Interfaces:**
- Produces: `Paster.Action` (enum, `.copyOnly`/`.synthesize`), `nonisolated static func action(autoPasteCapable: Bool, trusted: Bool) -> Action`, `init(monitor:autoPasteCapable:)` — Task 4·5가 사용.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/vClipsTests/PasterActionTests.swift`:

```swift
import XCTest
@testable import vClipsCore

final class PasterActionTests: XCTestCase {
    func testCopyOnlyWheneverNotCapable() {
        XCTAssertEqual(Paster.action(autoPasteCapable: false, trusted: true), .copyOnly)
        XCTAssertEqual(Paster.action(autoPasteCapable: false, trusted: false), .copyOnly)
    }

    func testSynthesizeOnlyWhenCapableAndTrusted() {
        XCTAssertEqual(Paster.action(autoPasteCapable: true, trusted: true), .synthesize)
        XCTAssertEqual(Paster.action(autoPasteCapable: true, trusted: false), .copyOnly)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter PasterActionTests 2>&1 | tail -5`
Expected: 컴파일 실패 — `type 'Paster' has no member 'action'`

- [ ] **Step 3: 최소 구현**

`Paster.swift`의 프로퍼티·init을 다음으로 교체하고 enum/함수를 추가:

```swift
@MainActor
final class Paster {
    /// Which way a paste request resolves. Pure decision, kept static so the
    /// matrix is unit-testable without AppKit.
    enum Action: Equatable { case copyOnly, synthesize }

    nonisolated static func action(autoPasteCapable: Bool, trusted: Bool) -> Action {
        (autoPasteCapable && trusted) ? .synthesize : .copyOnly
    }

    private let monitor: ClipboardMonitor
    /// false in the Mac App Store build: the AX/synthesis path is unreachable.
    private let autoPasteCapable: Bool

    init(monitor: ClipboardMonitor, autoPasteCapable: Bool = true) {
        self.monitor = monitor
        self.autoPasteCapable = autoPasteCapable
    }
    // paste(_:)/synthesizeCommandV()는 이 태스크에서 변경하지 않음 (Task 4)
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter PasterActionTests 2>&1 | tail -3`
Expected: `Executed 2 tests, with 0 failures`

- [ ] **Step 5: 커밋**

```bash
git add Sources/vClipsCore/Paste/Paster.swift Tests/vClipsTests/PasterActionTests.swift
git commit -m "feat(paste): variant flag + pure paste-action decision

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: AutoPasteOffer가 발화 여부를 반환 + 프레젠터 주입

**Files:**
- Modify: `Sources/vClipsCore/Paste/AutoPasteOffer.swift`
- Test: `Tests/vClipsTests/AutoPasteOfferTests.swift` (create)

**Interfaces:**
- Produces: `@discardableResult static func offerIfNeeded(present: @escaping @MainActor () -> Void = presentAlert) -> Bool` — true면 이번 복사의 안내를 알럿이 담당하므로 호출측(Task 4)은 토스트를 생략.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/vClipsTests/AutoPasteOfferTests.swift`:

```swift
import XCTest
@testable import vClipsCore

@MainActor
final class AutoPasteOfferTests: XCTestCase {
    private let key = "didOfferAutoPaste"

    override func setUp() { UserDefaults.standard.removeObject(forKey: key) }
    override func tearDown() { UserDefaults.standard.removeObject(forKey: key) }

    func testFiresExactlyOnce() {
        XCTAssertTrue(AutoPasteOffer.offerIfNeeded(present: {}))
        XCTAssertFalse(AutoPasteOffer.offerIfNeeded(present: {}))
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter AutoPasteOfferTests 2>&1 | tail -5`
Expected: 컴파일 실패 — `offerIfNeeded`에 인자·반환값 없음

- [ ] **Step 3: 구현 — 시그니처 변경, 알럿 본문은 private 함수로 이동**

`AutoPasteOffer.swift` 전체를 다음으로 교체:

```swift
import AppKit

/// One-time, contextual Accessibility onboarding, shown the first time the
/// user pastes without the permission — direct-distribution build only (the
/// MAS build never reaches this: its Paster is not autoPasteCapable). Never
/// prompts at launch; stays copy-only if declined.
@MainActor
enum AutoPasteOffer {
    private static let offeredKey = "didOfferAutoPaste"

    /// Returns true when the one-time offer fires. The alert's message text
    /// already says "copied — press ⌘V", so the caller skips the copy toast
    /// for that one paste.
    @discardableResult
    static func offerIfNeeded(present: @escaping @MainActor () -> Void = presentAlert) -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: offeredKey) else { return false }
        defaults.set(true, forKey: offeredKey)

        // Let the popup finish closing and focus settle before taking key
        // status for the alert.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            present()
        }
        return true
    }

    private static func presentAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Your clip was copied — press ⌘V to paste it"
        alert.informativeText = """
        vClips can also paste the selected clip into the app you're \
        using, automatically. To enable auto-paste, allow vClips under \
        System Settings → Privacy & Security → Accessibility. \
        vClips only ever uses this to press ⌘V for you.
        """
        alert.addButton(withTitle: "Enable Auto-Paste…")
        alert.addButton(withTitle: "Use Copy Only")
        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityPermission.prompt()
        }
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter AutoPasteOfferTests 2>&1 | tail -3`
Expected: `Executed 1 test, with 0 failures`

- [ ] **Step 5: 커밋**

```bash
git add Sources/vClipsCore/Paste/AutoPasteOffer.swift Tests/vClipsTests/AutoPasteOfferTests.swift
git commit -m "refactor(paste): AutoPasteOffer reports whether it fired

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: CopyToast HUD

**Files:**
- Create: `Sources/vClipsCore/UI/CopyToast.swift`
- Test: `Tests/vClipsTests/CopyToastTests.swift` (create)

**Interfaces:**
- Produces: `CopyToast.shared.show()` (@MainActor; 내부에서 `CopyToast.isEnabled` 검사), `nonisolated static var isEnabled: Bool` (`showCopyToast` 기본 true) — Task 4·6이 사용.

- [ ] **Step 1: 실패하는 테스트 작성 (게이팅 로직만 — 패널은 수동 검증)**

`Tests/vClipsTests/CopyToastTests.swift`:

```swift
import XCTest
@testable import vClipsCore

final class CopyToastTests: XCTestCase {
    private let key = "showCopyToast"

    override func setUp() { UserDefaults.standard.removeObject(forKey: key) }
    override func tearDown() { UserDefaults.standard.removeObject(forKey: key) }

    func testEnabledByDefault() {
        XCTAssertTrue(CopyToast.isEnabled)
    }

    func testDisabledWhenPreferenceOff() {
        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(CopyToast.isEnabled)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter CopyToastTests 2>&1 | tail -5`
Expected: 컴파일 실패 — `cannot find 'CopyToast'`

- [ ] **Step 3: 구현**

`Sources/vClipsCore/UI/CopyToast.swift`:

```swift
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
            NSAnimationContext.runAnimationGroup {
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
```

- [ ] **Step 4: 통과 + 빌드 확인**

Run: `swift test --filter CopyToastTests 2>&1 | tail -3 && swift build 2>&1 | tail -2`
Expected: `Executed 2 tests, with 0 failures` / `Build complete!`

- [ ] **Step 5: 커밋**

```bash
git add Sources/vClipsCore/UI/CopyToast.swift Tests/vClipsTests/CopyToastTests.swift
git commit -m "feat(ui): CopyToast — '⌘V to paste' HUD after copy-only copies

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Paster.paste 통합 (카피 전용 경로 + 토스트/오퍼 조율)

**Files:**
- Modify: `Sources/vClipsCore/Paste/Paster.swift` (paste(_:)만)

**Interfaces:**
- Consumes: Task 1의 `Action`/`action(...)`/`autoPasteCapable`, Task 2의 `offerIfNeeded() -> Bool`, Task 3의 `CopyToast.shared.show()`.

- [ ] **Step 1: paste(_:) 교체**

```swift
    func paste(_ content: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
        monitor.markSelfCopy()

        // && short-circuits: the MAS build (autoPasteCapable == false) never
        // evaluates isTrusted, so no AX API call can ever happen there.
        let trusted = autoPasteCapable && AccessibilityPermission.isTrusted
        switch Self.action(autoPasteCapable: autoPasteCapable, trusted: trusted) {
        case .copyOnly:
            // Direct build only: the one-time explainer replaces the toast
            // for that single copy (its message already says "press ⌘V").
            let offered = autoPasteCapable && AutoPasteOffer.offerIfNeeded()
            if !offered { CopyToast.shared.show() }
        case .synthesize:
            // Wait for the popup to close and focus to return to the previous
            // app before synthesizing ⌘V, so the keystroke lands in that app.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                self.synthesizeCommandV()
            }
        }
    }
```

`synthesizeCommandV()`와 파일 하단은 그대로 둔다.

- [ ] **Step 2: 전체 테스트·빌드 확인**

Run: `swift test 2>&1 | tail -3 && swift build 2>&1 | tail -2`
Expected: 전부 통과 / `Build complete!`

- [ ] **Step 3: 커밋**

```bash
git add Sources/vClipsCore/Paste/Paster.swift
git commit -m "feat(paste): copy-only path with toast; AX untouched when not capable

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: 플래그 배선 — AppEnvironment · 엔트리포인트 · MenuContent · PopupView

**Files:**
- Modify: `Sources/vClipsCore/AppEnvironment.swift`
- Modify: `Sources/vClipsCore/UI/MenuContent.swift:47-52`
- Modify: `Sources/vClipsCore/UI/PopupView.swift` (init + footer의 `KeyHint(key: "⏎", …)`)
- Modify: `Sources/vClipsAppStore/vClipsApp.swift:11`

**Interfaces:**
- Produces: `AppEnvironment.autoPasteCapable: Bool` (public let), `AppEnvironment.init(autoPasteCapable: Bool = true)`, `PopupView`의 `pasteKeyHintLabel: String = "Paste"` init 파라미터.

- [ ] **Step 1: AppEnvironment에 플래그 추가**

```swift
    /// false in the Mac App Store build: auto-paste (and every mention of
    /// Accessibility) is compiled in but unreachable there. Injected from the
    /// entry points, mirroring MenuContent/SettingsView's showsSupportLink.
    public let autoPasteCapable: Bool

    public init(autoPasteCapable: Bool = true) {
        self.autoPasteCapable = autoPasteCapable
```

같은 init 안에서:
- `self.paster = Paster(monitor: self.monitor)` → `self.paster = Paster(monitor: self.monitor, autoPasteCapable: autoPasteCapable)`
- `PopupView(model:…` 생성에 `pasteKeyHintLabel: autoPasteCapable ? "Paste" : "Copy",`를 `model:` 다음 인자로 추가.

- [ ] **Step 2: PopupView에 힌트 라벨 파라미터 추가**

PopupView의 저장 프로퍼티에 `let pasteKeyHintLabel: String`을 추가하고 기존 init에 `pasteKeyHintLabel: String = "Paste"` 파라미터를 넣어 저장한다 (기존 호출부는 기본값으로 무변경). footer의 231행을:

```swift
            KeyHint(key: "⏎", label: pasteKeyHintLabel)
```

- [ ] **Step 3: MenuContent 조건 수정**

47행의 `if !AccessibilityPermission.isTrusted {`를:

```swift
        // Hidden entirely in the MAS build; && short-circuits so the AX API
        // is never queried there either.
        if env.autoPasteCapable && !AccessibilityPermission.isTrusted {
```

- [ ] **Step 4: MAS 엔트리포인트에 플래그 주입**

`Sources/vClipsAppStore/vClipsApp.swift`의 `let env = AppEnvironment()`를:

```swift
    // Copy-only on the App Store: guideline 2.4.5 disallows Accessibility-
    // based paste synthesis, so this variant never offers auto-paste.
    let env = AppEnvironment(autoPasteCapable: false)
```

직배포 엔트리(`Sources/vClips/vClipsApp.swift`)는 기본값 `true`라 무변경.

- [ ] **Step 5: 빌드·테스트 확인**

Run: `swift build 2>&1 | tail -2 && swift test 2>&1 | tail -3`
Expected: `Build complete!` / 전부 통과

- [ ] **Step 6: 커밋**

```bash
git add Sources/vClipsCore/AppEnvironment.swift Sources/vClipsCore/UI/MenuContent.swift Sources/vClipsCore/UI/PopupView.swift Sources/vClipsAppStore/vClipsApp.swift
git commit -m "feat(mas): copy-only variant — autoPasteCapable flag wired end to end

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: 설정 토글

**Files:**
- Modify: `Sources/vClipsCore/UI/SettingsView.swift`

**Interfaces:**
- Consumes: Task 3의 `showCopyToast` 키 계약 (기본 true).

- [ ] **Step 1: 토글 추가**

`@State private var revertingLaunchAtLogin…` 아래에 프로퍼티 추가:

```swift
    @AppStorage("showCopyToast") private var showCopyToast = true
```

body의 launchAtLoginError 표시 블록(`if let launchAtLoginError { … }`) 바로 다음에:

```swift
            Toggle("Show a \u{201C}⌘V to paste\u{201D} reminder after copying",
                   isOn: $showCopyToast)
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build 2>&1 | tail -2`
Expected: `Build complete!`

- [ ] **Step 3: 커밋**

```bash
git add Sources/vClipsCore/UI/SettingsView.swift
git commit -m "feat(settings): toggle for the copy toast (default on)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: 실기 검증 (양 변형)

**Files:** 없음 (검증만). 참고: 라이브 데이터 안전 수칙 — 검증 전 스토어 백업(`~/Library/Application Support/vClips` 복사), 시드 항목만 조작.

- [ ] **Step 1: 직배포 변형 — 자동 붙여넣기 회귀 + 폴백 토스트**

```bash
./scripts/bundle.sh release && ditto --rsrc build/vClips.app /tmp/vClips-test.app && open /tmp/vClips-test.app
```
① AX 허용 상태: 클립 선택 → 대상 앱에 자동 붙여넣기 (토스트 없음)
② `defaults write com.vclips.app SimulateUntrusted -bool true` 후: 클립 선택 → 복사만 + 토스트 표시 (AutoPasteOffer는 이미 소진된 계정이므로 토스트 경로)
③ 설정에서 토글 OFF → 토스트 안 뜸. 확인 후 `defaults delete com.vclips.app SimulateUntrusted; defaults delete com.vclips.app showCopyToast`

- [ ] **Step 2: MAS 변형 — AX 완전 부재 확인**

```bash
./scripts/appstore.sh   # .pkg 생성
sudo installer -pkg dist/vClips-AppStore-*.pkg -target /   # 또는 pkg 더블클릭
tccutil reset Accessibility com.vclips.app
```
확인 항목: ① 메뉴에 "Grant Accessibility…" 없음 ② 클립 선택 → 복사 + 토스트, ⌘V 수동 붙여넣기 정상 ③ 팝업 푸터 힌트가 "⏎ Copy" ④ 어떤 조작에도 AX 권한 프롬프트가 뜨지 않고 시스템 설정 Accessibility 목록에 vClips가 등장하지 않음 ⑤ 설정 토글 동작

- [ ] **Step 3: 검증 후 로컬 원복**

직배포 1.2.4 정식본을 재설치(기존 절차: build/vClips.app → /Applications 교체)하고 `/tmp/vClips-test.app` 삭제.

---

### Task 8: 1.2.5 제출 준비 (운영)

**Files:**
- Audit: `dist/appstore-screenshots/` (auto-paste·Grant 메뉴 노출 컷 교체)
- 절차 상세: `.superpowers/sdd/2026-08-12-mas-resubmission-ops.md` (비공개)

- [ ] **Step 1: 스크린샷 감사** — 각 컷을 열어 auto-paste 흔적 확인, 있으면 새로 캡처
- [ ] **Step 2: ASC 메타데이터 확인** — 설명문에 auto-paste 문구 있으면 제거 (사용자와 함께)
- [ ] **Step 3: `./scripts/appstore.sh`로 1.2.5 .pkg 빌드**
- [ ] **Step 4: 사용자 핸드오프** — Transporter 업로드 + ASC 스레드 답신(문구는 비공개 노트에) + 심사 제출
- [ ] **Step 5: 결과 나오면 허브 022에 1줄 기록**
