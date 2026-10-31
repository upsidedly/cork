# Cork 0.9.0

A wall for your Mac, with a bundled Pinterest importer.

- Choose any two colours directly in Cork's main window. Pixel classification distinguishes strong colours from accents; wallpapers match actual selected image families and native display dimensions.
- Import Pinterest boards without an agent plugin. Choose 20/50/100/150/200/All per board, review keepers, then import with source and colour metadata. Explicit browser-cookie consent, memory-only credentials, scoped requests, resumable reviews and duplicate-safe recovery.
- Save named favourite corkboards and reload their layout, notes, widget state and wallpaper. Loading is undoable.
- Schedule rolls every minute, hour, day, week, morning/evening, or a custom interval. Off by default; editing defers a roll and sleep catches up once.
- First-run welcome, local media ownership, per-image visibility, note layout/overlay choices, automatic note colours, display-size adaptation and menu-bar wallpaper synchronization.
- Includes the local MCP bridge and widget support for Swingset's ten fidget toys.

## Install

Download `Cork-0.9.0-universal.dmg`, open it, and drag Cork into Applications. Requires macOS 14+, Apple silicon or Intel. Cork Importer is included inside the app. Personal Pinterest media is not included.

**Signing:** this community build is ad hoc signed, not Developer ID signed or notarized. macOS may require its **Privacy & Security → Open Anyway** flow for first launch. Do not disable Gatekeeper. See [Apple's instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac).

Accessibility is optional for minimizing other apps. Screen Recording is optional for requested desktop captures. Neither is needed for the collage/import flow. Browser Safe Storage access is requested separately by Cork Importer only after its disclosure and explicit consent.

Pinterest's unofficial website endpoints may change; Safari is not supported yet. An incomplete feed is reported rather than presented as a complete All import. Image rights remain with their owners. Source code: AGPL-3.0-or-later.

The `.sha256` file provides a checksum for the DMG. Updating the app preserves the data in `~/Library/Application Support/Cork`.
