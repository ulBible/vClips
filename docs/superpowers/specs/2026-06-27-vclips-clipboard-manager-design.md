# vClips — macOS 클립보드 매니저 설계

- **작성일:** 2026-06-27
- **상태:** 승인됨 (설계 완료, 구현 계획 대기)
- **용도:** 개인용 실사용 도구

## 한 줄 요약

⌘⇧V로 어디서든 띄우는, 텍스트 히스토리·검색·즐겨찾기를 갖춘 macOS 네이티브 클립보드 매니저.

## 확정 사항

- **플랫폼/스택:** Swift + SwiftUI 네이티브, 메뉴바 상주 앱 (`LSUIElement = true`, Dock 미표시)
- **MVP 기능:** 텍스트 히스토리, 검색, 즐겨찾기(고정)
- **접근 방식:** 글로벌 단축키 팝업 + 메뉴바 아이콘
- **붙여넣기:** 자동 붙여넣기 (Accessibility 권한 사용, 미허용 시 복사 전용 폴백)
- **저장:** SwiftData

비포함(추후 확장 여지): 이미지/파일 히스토리, iCloud 동기화, 스니펫, 단축키 커스터마이징 UI.

## 아키텍처

```
┌─────────────────────────────────────────────┐
│  vClipsApp (메뉴바 상주, LSUIElement=true)    │
├─────────────────────────────────────────────┤
│  ClipboardMonitor   ── NSPasteboard 폴링      │
│      │  (changeCount, 0.5초 타이머)           │
│      ▼                                        │
│  HistoryStore (SwiftData)  ── 저장/검색/정리  │
│      ▲                                        │
│  HotkeyManager  ── 글로벌 ⌘⇧V 등록            │
│      │                                        │
│      ▼                                        │
│  PopupWindow (SwiftUI)  ── 목록/검색/선택     │
│      │                                        │
│      ▼                                        │
│  Paster  ── 클립보드 set + ⌘V 합성(CGEvent)   │
└─────────────────────────────────────────────┘
```

각 컴포넌트는 독립적으로 테스트 가능한 단일 책임을 가진다.

## 컴포넌트 상세

### ClipboardMonitor
- `NSPasteboard.general.changeCount`를 0.5초 타이머로 폴링한다. (macOS는 클립보드 변경 알림 API가 없어 폴링이 표준 방식)
- changeCount가 바뀌면 `.string` 타입을 읽어 `HistoryStore`에 전달한다.
- **개인정보 보호:** 파스트보드에 `org.nspasteboard.ConcealedType`(비밀번호 관리자) 또는 `org.nspasteboard.TransientType`가 있으면 저장하지 않는다.
- **무한 루프 방지:** Paster가 직접 set한 직후의 changeCount는 무시한다 (자체 변경을 새 복사로 오인하지 않도록).

### HistoryStore (SwiftData)
- 모델: `ClipItem { id: UUID, content: String, createdAt: Date, isPinned: Bool, lastUsedAt: Date }`
- **중복 처리:** 동일 content가 들어오면 새 항목을 만들지 않고 기존 항목의 `lastUsedAt`을 갱신해 맨 위로 올린다.
- **자동 정리:** 고정되지 않은 항목은 최대 200개만 유지하고, 초과 시 가장 오래된 비고정 항목부터 삭제한다. 고정 항목은 개수 제한·정리 대상에서 제외한다.
- **검색:** `@Query` + 필터 술어로 content 부분 일치 검색.

### HotkeyManager
- Carbon `RegisterEventHotKey`로 글로벌 ⌘⇧V를 등록한다 (백그라운드에서도 동작하는 표준 방식).
- MVP는 단축키 고정. 추후 설정에서 변경 가능하도록 구조적 여지를 남긴다.

### PopupWindow + SwiftUI 뷰
- 단축키 입력 시 마우스 위치(또는 화면 중앙)에 작은 패널(`NSPanel`, nonactivating)을 표시한다.
- 상단 검색 필드 자동 포커스 → 타이핑하면 즉시 필터링.
- 키보드 전용 조작: ↑↓ 이동, ⏎ 선택·붙여넣기, ⌘F 고정 토글, esc 닫기.
- 즐겨찾기(고정) 항목은 목록 상단에 별도 그룹으로 표시한다.

### Paster
- 항목 선택 시: 내용을 `NSPasteboard`에 set → 팝업을 닫고 직전 앱으로 포커스 복귀 → `CGEvent`로 ⌘V를 합성한다.
- 붙여넣은 항목의 `lastUsedAt`을 갱신한다.
- Accessibility 권한이 없으면 ⌘V 합성을 생략하고 클립보드 set까지만 수행한다 (복사 전용 폴백).

## 데이터 흐름

### 복사 감지 → 저장
```
사용자 ⌘C → NSPasteboard 변경 → Monitor 폴링 감지
  → Concealed/Transient 검사 → 통과 시 HistoryStore.add()
  → 중복이면 기존 항목 맨 위로, 아니면 새 ClipItem 삽입
  → 비고정 200개 초과 시 오래된 항목부터 정리
```

### 조회 → 붙여넣기
```
⌘⇧V → PopupWindow 표시 (검색 필드 포커스)
  → (검색) 입력 시 @Query 필터링
  → ↑↓로 항목 선택 → ⏎
  → Paster: 클립보드 set → 팝업 닫기 → 직전 앱 복귀 → ⌘V 합성
  → lastUsedAt 갱신
```

## 핵심 난점 & 대응

- **권한(Accessibility):** 자동 붙여넣기에 필요. 첫 실행 시 안내하고 `AXIsProcessTrusted()`로 상태를 확인한다. 미허용이면 시스템 설정 딥링크를 안내하고, 권한이 없는 동안에는 "복사 전용" 모드로 자동 폴백한다.
- **포커스 복귀 타이밍:** 팝업이 닫히고 직전 앱이 키 포커스를 되찾은 뒤 ⌘V를 보내야 한다. `NSPanel`을 nonactivating으로 만들어 애초에 직전 앱의 포커스를 뺏지 않도록 하여 해결한다.
- **개인정보:** concealed/transient 타입 제외. 모든 데이터는 로컬에만 저장하고 네트워크 전송은 없다.
- **무한 루프 방지:** Paster의 자체 set으로 인한 changeCount 변화는 Monitor가 무시한다.

## 테스트 전략

- **단위 테스트(XCTest):** HistoryStore의 중복 병합·자동 정리(200개)·고정 유지 로직, Concealed/Transient 타입 필터링 로직. 순수 로직이라 테스트 용이.
- **수동 검증:** 글로벌 단축키 등록, 팝업 표시, 자동 붙여넣기 실제 동작, 권한 폴백 등 시스템 통합 부분.
- 구현은 TDD로 진행한다 (로직 우선, UI/시스템 통합은 수동 확인).

## 기본값 정리

| 항목 | 기본값 |
|------|--------|
| 폴링 주기 | 0.5초 |
| 비고정 히스토리 최대 개수 | 200개 |
| 글로벌 단축키 | ⌘⇧V |
| 콘텐츠 타입 | 텍스트(`.string`)만 |
