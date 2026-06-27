# vClips — 단축키 사용자 설정 기능 설계

- **작성일:** 2026-06-27
- **상태:** 승인됨 (설계 완료, 구현 계획 대기)
- **선행:** vClips MVP (텍스트 히스토리·검색·고정·자동 붙여넣기) 완료

## 한 줄 요약

메뉴바 → "설정…"에서 녹화식 레코더로 팝업 단축키를 변경하고, 즉시 적용·영구 저장한다. 기본값은 기존 ⌘⇧V를 유지해 마이그레이션이 필요 없다.

## 확정 사항

- **입력 방식:** 녹화식(레코더) — 필드 클릭 후 원하는 키 조합을 직접 눌러 지정.
- **구현:** `KeyboardShortcuts`(sindresorhus, MIT) 라이브러리 사용. 레코더 UI·UserDefaults 저장·전역 등록을 모두 제공하며, 기존 Carbon 기반 `HotkeyManager`를 대체한다.
- **저장:** `KeyboardShortcuts`가 `UserDefaults`(com.vclips.app 도메인)에 자동 저장. SwiftData는 사용하지 않는다.
- **기본값:** `.togglePopup` 단축키의 기본을 ⌘⇧V로 지정 → 기존 동작 보존.

## 아키텍처 / 컴포넌트

```
Package.swift           KeyboardShortcuts (SwiftPM) 의존성 추가
Sources/vClips/Hotkey/Shortcuts.swift
                        KeyboardShortcuts.Name.togglePopup 정의 (기본값 ⌘⇧V)
Sources/vClips/AppEnvironment.swift
                        HotkeyManager 제거, KeyboardShortcuts.onKeyDown(.togglePopup) 등록
Sources/vClips/Hotkey/HotkeyManager.swift
                        삭제 (라이브러리가 전역 등록 대체)
Sources/vClips/UI/SettingsView.swift
                        KeyboardShortcuts.Recorder("팝업 열기:", name: .togglePopup)
Sources/vClips/vClipsApp.swift
                        Settings 씬 추가 + 메뉴바에 "설정…" 항목
```

각 컴포넌트는 단일 책임을 가진다. `Shortcuts.swift`는 단축키 이름·기본값만, `SettingsView`는 설정 UI만, `AppEnvironment`는 트리거를 기존 `togglePopup()`에 연결만 한다.

## 데이터 흐름

### 설정
```
메뉴바 → "설정…" → Settings 창 표시
  → Recorder 클릭 → 새 키 조합 녹화
  → KeyboardShortcuts가 UserDefaults에 저장 + 전역 등록 즉시 교체
    (앱 재시작 불필요, 이전 단축키 자동 해제)
```

### 사용
```
새 단축키 누름 → KeyboardShortcuts.onKeyDown(.togglePopup)
  → AppEnvironment.togglePopup() → 기존 팝업 표시 흐름
```

## 엣지 케이스 / 에러 처리

- **시스템 예약/충돌 조합:** 라이브러리 기본 동작에 위임(등록 거부·경고). 빈 값으로 지우면 단축키 비활성화되며 메뉴바로만 팝업을 열 수 있다.
- **기존 사용자:** 기본값이 ⌘⇧V이므로 변경 없이 동작. UserDefaults에 저장값이 있으면 그것을 사용한다.
- **앱 시작:** `AppEnvironment.start()`에서 `KeyboardShortcuts.onKeyDown(for: .togglePopup)` 핸들러를 등록한다(저장값/기본값 자동 적용).

## 테스트 전략

- 전역 단축키 등록은 시스템 의존이라 단위 테스트가 어렵다(기존 `HotkeyManager`도 수동 검증이었음). 검증된 라이브러리에 위임한다.
- **단위 테스트:** `.togglePopup`의 기본값이 ⌘⇧V인지 확인하는 수준.
- **수동 검증:** 설정창에서 단축키 변경 → 새 단축키로 팝업 동작 → 이전 단축키 무효 → 빈 값 처리 → 앱 재시작 후 설정 유지.

## 의존성 메모

- `KeyboardShortcuts`는 로컬 전용(네트워크 접근 없음), MIT 라이선스, macOS 14 / Swift 6 호환.
- 안정 자체 서명과 번들 ID(com.vclips.app)가 갖춰져 있어 UserDefaults 저장이 정상 동작한다.
- 라이브러리 도입으로 "외부 의존성 0" 원칙은 이 기능에 한해 완화한다(레코더 직접 구현 대비 코드량·엣지케이스 위험을 크게 줄임).

## 범위 밖 (YAGNI)

- 단축키 여러 개(항목별 핫키 등) — 이번엔 팝업 토글 단축키 하나만.
- 설정창의 다른 환경설정(폴링 주기, 최대 개수 등 노출) — 추후 필요 시.
