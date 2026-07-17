# About Window & Brand Identity — Design

Date: 2026-07-17
Status: Approved by user

## Goal

Add an "About vClips" menu item that opens an About window, and establish
the maker identity shown there — reused across future apps.

## Brand identity (decided)

- Brand: **Chakchak Works** (Korean: 착착 웍스) — from 착착, the mimetic
  word for things snapping neatly into place; "Works" adds the
  workshop/collective feel and the "it just works" double meaning.
- Attribution format: `Made by Chakchak Works · by ulBible` — the brand
  leads; ulBible stays as the GitHub identity (hybrid decision).
- Tagline (EN): `Small Mac tools that snap right in.`
- Displayed copyright: `© 2026 Chakchak Works (ulBible). MIT License.`
  LICENSE file keeps `ulBible` as the legal holder; only display strings
  change.
- Verified available (2026-07-17): GitHub `chakchak-works`,
  `chakchak-studio` etc. free; domain `chakchak.works` has no DNS
  (likely purchasable). Bare `chakchak` handles are taken — acceptable,
  the GitHub identity remains ulBible.
- App Store constraint: the seller name stays "Sungkyung Kim" (individual
  account); the brand lives in About/README/GitHub only.

## About window

Use the native standard About panel (`NSApp.orderFrontStandardAboutPanel`)
with a custom credits attributed string. The system renders icon, app
name, and version automatically (CFBundleShortVersionString — no manual
version upkeep).

Credits content, in order:
1. Tagline: `Small Mac tools that snap right in.`
2. `Made by Chakchak Works · by ulBible`
3. Links (clickable): `GitHub` → https://github.com/ulBible/vClips ·
   `Support ❤️` → https://github.com/sponsors/ulBible ·
   `Privacy Policy` → https://github.com/ulBible/vClips/blob/main/PRIVACY.md

Copyright comes from Info.plist `NSHumanReadableCopyright` (updated to the
displayed-copyright string above), which the standard panel shows
automatically.

As an LSUIElement accessory, activate the app before showing the panel
(same pattern as Settings).

## Variant split (App Review guideline 3.1.1)

The Mac App Store build must not show the Support link:

- `AboutPanel.show(showsSupportLink:)` in vClipsCore.
- `MenuContent` gains `showsSupportLink: Bool = true` (default true), used
  for the About action; the vClipsAppStore entry point passes `false` —
  the same pattern as `SettingsView(showsSupportLink:)`.

## Menu placement

History / Check for Updates… (GitHub build only) / Settings… /
**About vClips** / (Grant Accessibility, when untrusted) / Quit.

## Also touched for consistency

- `Resources/Info.plist` — `NSHumanReadableCopyright` → new string.
- `README.md` — add one line under the title: `A Chakchak Works app.`

## Components

- `Sources/vClipsCore/UI/AboutPanel.swift` (new): builds the credits
  NSAttributedString and presents the standard panel.
- `Sources/vClipsCore/UI/MenuContent.swift`: new menu item + parameter.
- `Sources/vClips/vClipsApp.swift` / `Sources/vClipsAppStore/vClipsApp.swift`:
  pass the variant flag.

## Testing

- Unit: none needed beyond existing suite (presentation-only feature);
  build both variants.
- Manual: open About from the menu in the GitHub build (links present,
  version correct) and in a MAS smoke build (no Support link).

## Out of scope

- Custom SwiftUI About window (rejected: native panel fits the brand and
  needs no upkeep).
- Domain purchase (chakchak.works) and separate GitHub org — later, when
  needed.
- Localized (Korean) About strings — English only for now, matching the
  rest of the app.
