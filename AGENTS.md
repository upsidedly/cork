# Cork

Native macOS utility. Swift 6, macOS 14+, SwiftPM; no third-party runtime dependencies.

- Build: `./scripts/build.sh` → `build/Cork.app`, including `Contents/MacOS/cork-mcp`.
- Focused checks: `./scripts/check.sh` (dependency-free `CorkChecks` executable; this host's Command Line Tools lacks Swift Testing).
- Do not change global Xcode selection or accept Xcode agreements. `CORK_SDK` selects a task-scoped SDK; default is the installed Command Line Tools macOS 26.5 SDK.
- Quit the running Cork before rebuilding its signed bundle. Overwriting a running signed executable can cause macOS to terminate it.
- Use explicit `CORK_DATA_DIR` and `CORK_SOCKET` for both app and bridge when testing. Do not overwrite a user's real board with sample artwork.
- The running app owns all board writes. MCP goes through the protected Unix socket; preserve atomic batch edits, increasing revisions and undo. Never retry a mutation after an ambiguous response failure.
- Blocking socket callbacks must be created outside MainActor; accepted Darwin sockets must explicitly clear inherited `O_NONBLOCK`. Both contracts have runtime checks.
- UI/persistence boundaries and rendering live in `docs/DEVELOPMENT.md`; source provenance and limits are in `docs/RESEARCH.md`. No copied Übersicht or PinMark source/assets.
- In the library's `HSplitView`, keep both children explicitly sized to available height, including the no-selection state. An intrinsic-height placeholder previously collapsed the item list into the center.
- Screenshots require macOS Screen Recording permission for Cork. Report permission denial truthfully; do not modify TCC databases or bypass the system authentication flow.
- Match Tuck/Snap's README and native monochrome icon family. The print/note content is intentionally physical; app controls remain standard native controls.
- `collection.json` is a real user's curated photo pool, separate from `board.json`. Preserve its metadata and local media; do not replace either with test fixtures. Collection imports and dice rolls go through the running app, and a roll must preserve notes, other displays, undo and blank captions.
- `wallpapers.json` is also user data owned by the running app. Wallpaper imports measure actual pixels and colours; automatic selection must satisfy native-resolution and crop-retention limits. Never upscale thumbnails to make them eligible.
- Fill Empty preserves every existing item's geometry; kept images survive rolls and automatic arrangement too. Palette, wallpaper and photo changes commit and undo as one scene. Both Carbon shortcuts share one application event handler and retain their old registrations until a proposed settings save succeeds.
- A note's `includeInLayout` defaults to true for legacy data. Overlay notes (`false`) never consume packing space or move during arrangement, and render after every photo via `Board.itemsBackToFront`, regardless of newer photo z-indices. Preserve both note kinds through rolls and Fill Empty.
