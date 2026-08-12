# MAS 카피 전용 빌드 — 설계

2026-08-12 · 상태: 승인됨 · 대상: vClips 1.2.5 (MAS 재제출)

## 배경

Mac App Store 가이드라인 2.4.5는 Accessibility API를 접근성 외 목적으로
사용하는 것을 금지하며, 자동 붙여넣기를 위한 ⌘V 합성이 여기에 해당한다.
macOS의 모든 키 입력 합성 경로가 같은 동의 체계 뒤에 있으므로 우회 수단은
없다. 결정: MAS 변형은 카피 전용으로 가고, GitHub/Homebrew 변형은 자동
붙여넣기를 그대로 유지한다.

## 목표

- MAS 빌드는 Accessibility를 요청하지도, 언급하지도, 코드 경로로 진입하지도
  않는다.
- 카피 전용 UX의 편의 손실을 최소화한다: 클립 선택 후 ⌘V 한 번이면 되고,
  토스트가 그 사실을 알려준다.
- 직배포 빌드의 동작은 변하지 않는다 (단, 그동안 무반응이던 권한 미허용
  폴백에도 같은 토스트가 추가되어 오히려 개선).
- 앱 안 어디에서도 MAS 외 버전으로 유도하는 문구를 넣지 않는다.

## 비목표

- 이번 변경으로 GitHub 릴리스는 내지 않는다 (토스트 개선은 다음 정기
  릴리스에 자연 포함).
- 두 빌드가 공유하는 Paste/ 소스의 이름 변경·삭제는 하지 않는다.

## 설계

### 1. 변형 플래그

`AppEnvironment(autoPasteCapable: Bool)` — 기존 `showsSupportLink` 패턴을
따라 엔트리포인트에서 주입한다:

- `Sources/vClips/vClipsApp.swift` → `true`
- `Sources/vClipsAppStore/vClipsApp.swift` → `false`

UI는 환경 객체에서 플래그를 읽는다(`env.autoPasteCapable`). vClipsCore는 두
실행 파일이 공유하는 단일 모듈이므로 컴파일 분기가 아닌 런타임 주입이 맞다.

### 2. Paster 동작

`Paster.paste(_:)`에서 `autoPasteCapable == false`일 때:

- 지금처럼 페이스트보드 복사 + `markSelfCopy()`까지 수행하고,
- 토스트를 표시(설정이 켜져 있으면)한 뒤 종료 — `AccessibilityPermission.isTrusted`
  검사, `AutoPasteOffer`, CGEvent 합성이 **전부 실행되지 않는다**. 코드
  경로가 도달 불가능하므로 권한 프롬프트가 뜰 방법 자체가 없다.

`autoPasteCapable == true`일 때: 기존 동작 그대로. 단, 권한 미허용 폴백
분기에서도 토스트를 표시한다 (1회성 AutoPasteOffer 이후의 침묵을 대체).

### 3. CopyToast

새 파일 `Sources/vClipsCore/UI/CopyToast.swift`:

- 포커스를 뺏지 않는 플로팅 `NSPanel` HUD.
- 문구: `Copied — press ⌘V to paste`.
- 위치: 활성 화면 상단 중앙, 메뉴바 아래.
- 수명: 약 1.2초 후 페이드아웃. 연속 복사 시 패널을 중첩하지 않고 같은
  패널의 타이머를 리셋한다.
- 표시 조건: **합성 없이 복사만 한 모든 경우** (두 변형 공통), 설정
  `showCopyToast`가 켜져 있을 때.

### 4. MAS UI에서 AX 흔적 제거

- `MenuContent.swift`: "Grant Accessibility (for auto-paste)…" 항목은
  `autoPasteCapable == false`면 렌더링하지 않는다.
- 구현 시 사용자 노출 "paste" 계열 문구를 전수 감사한다 (PopupView
  힌트·툴팁, 설정, 메뉴): 실제로 붙여넣지 않는 MAS에서는 "copy" 워딩으로.
- 자동 붙여넣기가 다른 곳에 존재한다는 언급을 앱 안에 넣지 않는다.

### 5. 설정

`SettingsView`에 토글 한 줄 추가 (양 변형 공통):
"Show a '⌘V to paste' reminder after copying" — `UserDefaults` 키
`showCopyToast`, 기본값 `true`.

### 6. 재제출

`scripts/appstore.sh`로 1.2.5 빌드. 스토어 제출 관련 세부 절차는 공개
스펙이 아닌 비공개 운영 노트(`.superpowers/sdd/`)에 둔다.

### 7. 검증

- MAS 번들 로컬 설치: AX 프롬프트·메뉴 항목이 어디에도 없음; 클립 선택 →
  복사 + 토스트; `tccutil reset Accessibility com.vclips.app` 후 재시험해도
  어떤 경로로도 권한 요청이 발생하지 않음.
- 직배포 빌드: 자동 붙여넣기 회귀 확인(권한 허용 상태) + 미허용 폴백에서
  토스트 확인.
- 유닛: 플래그를 주입한 Paster 카피 전용 경로 (합성 시도 없음).
