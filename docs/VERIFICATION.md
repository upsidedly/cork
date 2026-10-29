# Verification

Cork **0.6.0, build 12**, verified 28 October 2026 on Apple Silicon, macOS 27.2 (26B118), Swift 6.3.2 and the Command Line Tools macOS 26.5 SDK. Deployment target remains macOS 14+. No global Xcode selection or license changes were made.

## Verdict

**BLOCKED — desktop capture still needs Screen Recording access.** The implemented layout, colour, visibility, external-widget and Swingset integration paths have passing evidence below. Accessibility was refreshed on 29 October 2026: the stale entry was removed after the user authenticated with Touch ID, and `/Applications/Cork.app` was re-added through System Settings. The running app confirmed access and live trackpad contact monitoring. No TCC database was modified. Actual cross-app minimization and physical third-finger gesture recognition remain unverified; an active contact monitor does not establish either behavior.

This does not block importing, arranging, rolling, note editing or interactive local widgets. Cork remains installed in Applications with native login registration enabled. Test copies used separate bundle IDs, explicit private data roots and a separate socket; fixtures never replaced the user's board or media.

## Build and model checks

- Final release app and bundled MCP compile without warnings. Info.plist validation and strict deep signature verification pass for the installed bundles.
- **49/49 Cork checks pass.** They cover atomic edits, aspect ratios, note styles, persistence/recovery, undo/redo, protected sockets, MCP lifecycle/schemas, legacy migration, image/video wallpaper ownership/settings, coherent mixed-board selection, source diversity, greedy packing, colour analysis, native-resolution wallpaper eligibility, shortcut validation and the anchored-gesture detector.
- New coverage includes note layout participation, overlay ordering, blue-wall/pink-background rejection, coordinate anchoring with stable photo identities/styles/angles, hidden-item retention/reflow, display growth/shrink, automatic note tint, widget resource ownership/recovery, traversal/symlink rejection, state bounds and separate automatic placement for repeated widgets.
- Swingset **0.1.0, build 2** also builds cleanly. Its **21/21 deterministic model checks** cover ten interactive toys, finite restored state, inertia/damping, gears, bead constraints, magnetic attraction, spring settling, zipper detents, cradle momentum and serialization. See [Swingset's record](https://github.com/Upsidedly/swingset/blob/main/docs/DEVELOPMENT.md).

## Native controls and persistence

Actual native apps were inspected and operated on this Mac:

- The Cork sidebar fills the available height, including the no-selection state. The former tiny centered list does not recur.
- A note's **Match collage colours** checkbox changed yellow paper to a pale blue/grey sampled from the fixture's blue photos. Manual paper controls disabled while matching; the manual colour remained stored.
- Typing X = 900 and pressing Return held the participating note at that exact coordinate. Existing photo IDs, assets, treatments and angles remained unchanged while positions reflowed. Dragging the adjacent Y slider committed Y = 642 and refit the photos.
- **Include in layout** switched off in the real inspector. Moving the resulting overlay note left every photo field unchanged. Prior native tests also verified both Flat and Sticky participation, Undo/Redo and public front-to-back window ordering above newer photos.
- An eye-button click hid a print and updated its native row to Hidden. Show, Undo and Redo restored the expected visibility. No media or item identity was deleted.
- Exact isolated restart comparisons preserved board items, geometry, note choices, desktop options and per-instance widget states. A final restart of the installed normal app also preserved all 26 items, revision 103, the wallpaper and desktop options exactly; native login registration remained enabled. Swingset restored ten saved toy states, the selected toy, and Sound/Haptics preferences.

## Real display changes

The system display setting was changed from **1800 × 1169** logical points to **1512 × 982**, then restored to the user's original **1800 × 1169**. Cork responded to actual macOS screen notifications without a manual arrangement command.

On shrink, all 19 existing item IDs remained and every visible decorated bound fit the new safe area. On growth, Cork preserved every smaller-layout item exactly and added **five** matching photos into the extra space. The final original display setting is restored. Subsequent widget placement retained those photos and the user's note; public geometry checks find no offscreen items or overlapping decorated bounds in the current scene.

The density cap and repeated resize behavior also have deterministic model coverage. A physical second monitor, display disconnect/reconnect and older supported macOS runtimes were not exercised on hardware.

## Local widget integration

The native Swingset app rendered all ten toys and exercised their actual pointer and/or keyboard controls. Bubble Wrap saved two popped bubbles; Clicker counted three inputs once each; switches flipped; gears rotated together; an abacus bead slid to the far side; magnets separated and attracted; elastic returned; the zipper moved; and the cradle transferred motion to the opposite end.

**Add to Cork** registered all ten definitions and copied the package, transferring the selected toy's state and preferences. After Swingset quit, the live Cork preview still ran. Playing it advanced its independent bubble count from two to four, saved without changing the layout revision, and survived layout Undo and an app restart. A separate complete counter provider from `docs/examples/counter` registered, rendered and saved a native button click from three to four, demonstrating that the registry is not specific to Swingset.

The first native host check found WebKit's rejection of regex disjunctions in content rules. The repair uses separate protocol rules; the actual source rules compile in WebKit. A loaded widget canary ran local JavaScript but HTTP fetch/image requests never reached a loopback test server, and an outside fixture file was denied. The server was stopped afterward. No new access was granted to test apps.

The installed normal Swingset pinned a Spinner and Bubble Wrap to the user's real wall. The second pin chose separate space around the first and the fixed note. Existing photo IDs/assets and note content were retained; the package is registered from the Applications copy. Both toys are available in Cork independently of the Swingset window. The other eight remain available through Swingset and Cork's Add Widget menu.

Human evaluation is still needed for the physical feel of haptics, subjective sound satisfaction and touch/VoiceOver workflows. A local live widget preview is interaction evidence, not a desktop screenshot or proof of physical trackpad feedback.

## Colour and private media

The user's photo catalogue retains **160 photos** and ten mixed-board visual moods, with original source metadata and managed assets present. The wallpaper catalogue contains **32** entries: the prior 24 Pinterest sources plus **eight reviewed large Unsplash originals**, from 4608 × 3072 up to 8256 × 5504 before managed normalization. Four small/portrait candidates were rejected. Automatic candidates still require both native display dimensions and at least 60% crop retention; thumbnails were not enlarged.

The rejected pink paint wallpaper is retained with `automatic: false`, excluding it from automatic selection. Wallpaper matching now checks the dominant hue family of the actual selected photos, not only a broad preset. Seeded blue-photo regression renders no longer select pink/purple paint. Ten mood canaries and representative native offscreen scenes were inspected. These are sampled layout renders, not desktop captures or a claim that every randomized result has been reviewed.

The current user's neutral Monochrome shore wallpaper was preserved through installation, display tests and widget pins. Private downloaded media and manifests remain in Application Support, outside versioned assets. Only authored sample artwork is bundled in documentation.

## Remaining OS-dependent checks

- Accessibility refresh is complete for build 12. The running app reported access, both shortcuts registered and live contact frames after re-adding the Applications bundle; the saved board remained unchanged. Future ad hoc rebuilds can require another permission refresh.
- Refresh its existing Screen Recording entry and relaunch if requested. The desktop screenshot MCP currently returns an explicit permission error; no denied capture is reported as a screenshot.
- With access available, exercise the actual one-way minimize shortcut twice and verify the physical two-anchored-fingers/third-finger downward gesture. The raw contact monitor correctly stays off without Accessibility. The configurable minimize and randomize shortcuts register successfully; hardware gesture checks are not inferred from pure detector tests.

No logout/reboot, full VoiceOver pass or macOS 14–26 runtime pass was performed. App restart persistence, the native login registration state and the applicable model/native cases above are verified separately.
