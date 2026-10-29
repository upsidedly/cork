# Reference research

Inspected 2026-10-28. Cork is an original implementation of platform behaviors and the requested interaction. No Übersicht or PinMark source, artwork, trademark or binary is included.

## Übersicht — source observed

Pinned source commit: `859a7d70525949b8bdeec19d69a4766678ca3527`, [felixhageloh/uebersicht](https://github.com/felixhageloh/uebersicht/tree/859a7d70525949b8bdeec19d69a4766678ca3527). GPL-3.0-or-later. The reference app was not installed or executed.

| Question | Source and finding | Cork choice |
| --- | --- | --- |
| Desktop placement | `Uebersicht/UBWindow.m`: borderless clear nonopaque windows; stationary, all Spaces, ignored window cycling. Background at desktop level; foreground at normal level minus one. | Native clear panels below desktop icons while locked; explicit foreground edit mode. |
| Pointer routing | `server/src/detectWidgetHover.js` and `UBWebViewController.m`: JS hover messages flip native `ignoresMouseEvents`. | Locked prints always pass mouse events through. Explicit Edit Desktop avoids hover detection and WebKit. |
| Displays | `UBScreensController.m`, `UBWindowsController.m`, `UBWindowGroup.m`: screen IDs and change notifications own per-display window groups. | CoreGraphics display IDs, screen-change observation, saved per-display coordinates and temporary fallback. |
| State | `server/src/Settings.js`, `app.coffee`: Node/Redux state, JSON settings, watched widget files. | One native board owner and atomic JSON persistence, no web runtime. |
| Automation | `Uebersicht.sdef`: AppleScript list/refresh/show/hide; loopback state/WebSocket sync internally. No MCP found in inspected source. | A private Unix socket connects stdio MCP to the app. |

README references to an interaction shortcut and Accessibility appear historical relative to the inspected pointer implementation. Static source does not establish behavior on this Mac; Cork requires its own runtime checks.

## PinMark Sticky — shipped bridge and documented native behavior

The native app was not installed locally. Official download links led to [Mac App Store 6758331413](https://apps.apple.com/app/id6758331413); a freely downloadable native artifact was not found within this search. Native internals, drawing geometry, window levels and persistence are therefore **unverified**. The documented version was 1.10.0, dated 2026-10-27.

Official references:

- [Image guide](https://pinmark.space/pin-photos-to-mac-desktop): image imports, tape/pushpin/Polaroid/frame styles, free placement and rotation.
- [User guide](https://pinmark.space/guide): autosaved geometry, Polaroid captions, independent float-on-top setting, photo wall arrangements and restore.
- [MCP](https://pinmark.space/mcp) and [changelog](https://pinmark.space/changelog).

The published MIT-licensed `@pinmark/mcp` **0.2.0** package was downloaded and statically inspected, including REA analysis. Artifact: `https://registry.npmjs.org/@pinmark/mcp/-/mcp-0.2.0.tgz`. SHA-256: `5e081d480619f83373a8ee8251372bf892ae768eedab746523cf59aba7a9c984`.

REA parent evidence: `ev_c95b59a734d5986c711802696e8ed3ee36bf556f3384b7e6aa6dd45b7e422a75`; summary: `ev_99d92d9da147cdbb560bc06aa256210b62710e5e1450a5d4658f5d6aad2bf625`. Three JavaScript files parsed, no parse failures; static relationship coverage is partial and does not prove runtime behavior.

`dist/index.js` uses stdio, with diagnostics on stderr. `dist/pinmark.js` locates the native CLI, spawns it with structured argv and a timeout, sends content on stdin, and normally uses `--no-activate`. The app owns persistence. `dist/server.js` exposes create/update/read/search/trash/restore/show/hide **text notes**. It does not expose image import, coordinates, desktop capture, rotation or arrangement. “Pin” is desktop visibility, distinct from floating above apps.

Cork adopts the app-owned state boundary and adds the requested image/note/spatial/capture tools with original Swift code. It does not clone PinMark's implementation or claim access to its proprietary source.

## Tuck and Snap

Read the local sibling READMEs, build/icon scripts and native icon marks at `../Tuck` and `../Snap`. Cork uses their centered README structure and matching off-white icon tile with a compact ink glyph. Cork's pinned-print glyph and demonstration artwork are authored for this project. Build tooling follows the same dependency-free SwiftPM app-bundle pattern.

## Protocol and platform sources

- [MCP stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports): UTF-8 JSON-RPC, one message per line, diagnostics on stderr.
- [ScreenCaptureKit screenshot manager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager): macOS 14+ screenshot capture and native permission boundary.

Pinterest is intentionally external: the installed plugin downloads selected images and supplies verified local paths. Cork stores optional provenance URLs but neither authenticates to Pinterest nor scrapes pages.


## Global minimize and the anchored trackpad gesture

Public API contracts were checked in the installed SDK headers (`HIToolbox/CarbonEvents.h`, `HIServices/AXAttributeConstants.h`) and Apple's [AX attribute setter](https://developer.apple.com/documentation/applicationservices/axuielementsetattributevalue(_:_:_:)) and [Accessibility element API](https://developer.apple.com/documentation/applicationservices/axuielement_h). Exclusive Carbon hotkeys expose collisions; `AXMinimized` is a writable Boolean whose true value minimizes a window. These primitives allow one-way minimization without Show Desktop or app hiding.

Apple's [touch event guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html) describes view-targeted touch events. It does not provide the requested global, two-stationary-fingers plus moving-third gesture. The private system `MultitouchSupport.framework` was therefore isolated behind a runtime availability check. ABI facts were cross-checked against the primary [macOSMiddleClick source](https://github.com/SomeGuyNamedDaveIsTaken/macOSMiddleClick/blob/main/middleclick.c): a 96-byte contact record, normalized positions at offset 32, live contact states 3/4, device enumeration/dimensions, callback registration and device start/stop. Cork copies no implementation from that project; its binding, detector and lifecycle are original. Static ABI checks cannot guarantee behavior after an OS update. The private gesture dependency remains an explicit distribution/compatibility limitation.

Greedy packing is also original: maximal free rectangles, native image/decorated ratios, bounded seeded candidates and a largest-hole penalty. No layout package or external recommendation service is embedded. Personal source images retain their existing local provenance and are not added to source or documentation assets.

## Coordinated scenes and widget coverage

Colour conversion follows Björn Ottosson's published [OKLab definition and matrices](https://bottosson.github.io/posts/oklab/), inspected 2026-10-28. Cork's bounded dominant-colour extractor, curated palettes, background hue scoring and photo-ranking rules are original. Perceptual distance supplies a repeatable colour signal; it does not establish artistic compatibility without rendered review.

Apple documents desktop widgets in the [Mac User Guide](https://support.apple.com/guide/mac-help/add-and-customize-widgets-mchl52be5da5/mac) and native stacking through [NSWindow.Level](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct). Installed CoreGraphics/AppKit SDK declarations were also inspected. Actual public owner/layer/bounds metadata on this host identified two Notification Centre widget windows at desktop-icon level +2. This is a host observation, not an Apple guarantee for every release. Cork places removable wallpaper covers above those surfaces and restores the original view on exit. It does not rewrite Apple's widget settings, inspect widget text or request screen capture to locate them.

The private wallpaper catalogue contains selected Pinterest downloads with their original pin links and honest board/discovery labels. Dimensions and colour samples are measured locally; no search thumbnail is upscaled to meet eligibility. These personal assets are not included in the repository or redistributed with the application. No Unsplash runtime service, recommendation API, image-analysis dependency or new network listener was added.
