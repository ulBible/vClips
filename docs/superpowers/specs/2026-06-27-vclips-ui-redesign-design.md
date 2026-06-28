# vClips — 팝업 UI 전면 개편 설계

- **작성일:** 2026-06-27
- **상태:** 승인됨 (설계 완료, 구현 계획 대기)
- **선행:** vClips MVP + 자동 붙여넣기/서명 수정 + 단축키 설정 (main에 병합 완료)

## 한 줄 요약

Raycast/Spotlight 풍 반투명 글래스 팝업으로 재단장한다. 즐겨찾기/최근을 섹션으로 분리해 가시성을 해결하고, 타입 아이콘과 호버 액션(★ 즐겨찾기 토글, × 삭제), 긴 항목 미리보기를 더한다.

## 동기

현재 팝업은 검색창 + 평범한 `List`이고, 즐겨찾기는 ⌘F 단축키로만 가능하며 작은 핀 아이콘만 붙어 "보이지 않는다"는 문제가 있다. 시각적 위계와 조작 affordance를 갖춘 네이티브 macOS UI로 끌어올린다.

## 확정 사항

- **비주얼:** 반투명 글래스(vibrancy). 배경을 `NSVisualEffectView`로 교체.
- **즐겨찾기:** 상단 "FAVORITES" 섹션 + "RECENT" 섹션으로 분리(헤더 표시).
- **행:** 타입 아이콘 + 내용 1줄(말줄임). 호버/선택 시 우측에 ★(즐겨찾기 토글)·×(삭제) 버튼.
- **스마트 타입 아이콘:** 내용 감지(url/email/filePath/text).
- **항목 삭제(신규):** 호버 × 및 ⌫(Delete) 키로 개별 삭제.
- **긴 텍스트 미리보기:** 선택 항목이 길거나 여러 줄이면 하단에 미리보기.
- **폭 유지:** 380pt. 높이는 콘텐츠/미리보기에 따라 가변(~460pt).

## 아키텍처 / 변경 파일

```
Sources/vClips/UI/PopupController.swift   글래스 배경(NSVisualEffectView) 적용
Sources/vClips/UI/PopupView.swift         섹션 리스트·행·호버 액션·미리보기로 재작성
                                          (RowView 등 하위 뷰는 같은 파일 내 분리)
Sources/vClips/UI/PopupViewModel.swift    섹션 분리, deleteSelected(), 선택 인덱스 보정
Sources/vClips/Store/HistoryStore.swift   delete(_:) 추가
Sources/vClips/UI/ContentType.swift       (신규) 타입 판별 순수 함수 + SF Symbol 매핑
```

각 단위는 단일 책임을 가진다. `ContentType`은 순수 함수로 분리해 독립 테스트하며, `HistoryStore`는 데이터 변경만, `PopupViewModel`은 표시·선택·액션 상태만 담당한다. `PopupView`가 커지면 `RowView`/`SectionHeader`/`PreviewPane`를 같은 파일 내 작은 뷰로 분리한다.

## 레이아웃

```
┌────────────────────────────┐
│ 🔍  Search…                 │  검색 필드(글래스 위 plain, 자동 포커스)
├────────────────────────────┤
│ ★ FAVORITES                 │  고정 항목이 있을 때만
│   🔑 api_key=sk-1234…    ★ ×│
│ 🕐 RECENT                   │
│ ▌🔗 https://example.com  ★ ×│  ← 선택(알약 하이라이트) + 호버 액션
│   ✉️ john@example.com        │
├────────────────────────────┤
│ 선택 항목 미리보기(여러 줄)   │  긴 텍스트일 때만 표시(가변 높이)
└────────────────────────────┘
```

검색어가 있으면 섹션 헤더 없이 결과만 표시하되 고정 항목을 먼저 정렬한다.

## 컴포넌트 상세

### ContentType (신규, 순수 함수)
- `enum ContentType { case url, email, filePath, text }`
- `static func detect(_ text: String) -> ContentType` — 트림 후: 이메일 정규식 → URL(`http(s)://` 접두 또는 호스트 패턴) → 파일경로(`/`나 `~/` 시작) → 그 외 `text`.
- `var symbolName: String` — `link` / `envelope` / `doc` / `doc.on.clipboard`.

### HistoryStore.delete
- `func delete(_ item: ClipItem)` — 컨텍스트에서 삭제 후 save. 고정 여부와 무관하게 삭제한다.

### PopupViewModel
- 표시용으로 결과를 두 그룹으로 노출: `favorites: [ClipItem]`(isPinned, lastUsedAt desc), `recents: [ClipItem]`(비고정, lastUsedAt desc). 검색어가 있으면 `recents`에 일치 결과(고정 먼저)만 담고 `favorites`는 비운다 — 즉 검색 시 단일 목록.
- 선택은 표시 순서(favorites + recents를 이어붙인 평탄 목록) 기준 단일 `selectedIndex` 유지. `moveSelection`/`chooseSelected`/`togglePinSelected`는 이 평탄 목록 기준.
- `deleteSelected()` — 선택 항목을 `store.delete` 후 `refresh()`하고 `selectedIndex`를 범위 내로 보정.
- 기존 인터페이스(`query`, `refresh()`, `moveSelection(_:)`, `chooseSelected()`, `togglePinSelected()`)는 유지.

### PopupView
- 글래스 위에 검색 필드 + 섹션(ScrollView/LazyVStack 또는 List) + 미리보기.
- 행(`RowView`): 타입 아이콘, 내용 1줄, 호버/선택 시 ★·× 버튼. 선택 시 알약 하이라이트. 탭 → 붙여넣기, ★/× 탭 → 각 동작.
- 키보드: ↑↓ 이동, ⏎ 붙여넣기, ⌘F 즐겨찾기 토글, **⌫ 삭제**, esc 닫기.
- 미리보기(`PreviewPane`): 선택 내용이 60자 초과이거나 개행 포함이면 하단에 최대 ~4줄 표시, 아니면 숨김.

### PopupController
- 패널 `contentView`를 `NSVisualEffectView`(material `.hudWindow` 또는 `.popover`, `blendingMode = .behindWindow`, `state = .active`)로 감싸고 그 위에 `NSHostingView`를 올린다. 둥근 모서리/그림자 적용.

## 데이터 흐름

```
[표시]  togglePopup → viewModel.refresh()
  → store.search(query) → favorites/recents 분리 → PopupView 렌더(글래스)

[즐겨찾기] ★ 클릭 또는 ⌘F → viewModel.togglePinSelected() → store.togglePin → refresh
[삭제]    × 클릭 또는 ⌫    → viewModel.deleteSelected() → store.delete → refresh + 인덱스 보정
[붙여넣기] 행 클릭 또는 ⏎  → 기존 choose 흐름(클립보드 set → 닫기 → ⌘V)
```

## 엣지 케이스

- **빈 상태:** 히스토리/검색 결과 없음 → "No items" placeholder.
- **즐겨찾기 없음:** FAVORITES 헤더 숨김(RECENT만).
- **검색 중:** 섹션 헤더 없이 단일 목록, 고정 먼저.
- **삭제 후:** selectedIndex가 목록 끝을 넘으면 마지막 항목으로 보정, 비면 0.
- **미리보기:** 짧은 항목이면 영역 미표시(높이 안정).

## 테스트 전략

- **단위(XCTest):**
  - `ContentType.detect` — url/email/filePath/text 각 케이스.
  - `HistoryStore.delete` — 고정/비고정 삭제, 삭제 후 목록 반영.
  - `PopupViewModel` — favorites/recents 분리, 검색 시 단일 목록, `deleteSelected()` 후 인덱스 보정.
- **수동:** 글래스 외형, 호버 액션 등장, 알약 하이라이트, ⌫ 삭제, 미리보기 표시/숨김, 빈 상태.

## 범위 밖 (YAGNI)

- 이미지/파일 콘텐츠 썸네일(현재 텍스트 전용).
- 드래그 정렬, 다중 선택, 태그/폴더.
- 하단 단축키 힌트 바(이번 선택에서 제외).
- 사용 빈도 기반 정렬(현재 고정 먼저 → 최근순 유지).
