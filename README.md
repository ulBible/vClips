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
