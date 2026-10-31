# Verification

## 0.9.0 build 17 desktop focus correction — 30 October 2026

The native arm64 app builds without warnings. Focused AppKit checks pass **4/4**: first-press selection/move and one commit, successive moves after the panel origin changes, finishing editing cancels a drag and locks the paper, and resizing preserves aspect ratio and position. They use hidden test windows and reuse the existing build cache.

With an isolated two-item board and eight existing image hardlinks, clicking the wallpaper followed by **⌘R** produced a saved collage. **⌘Z** restored the original items, and **⌘L** opened the library. Native inspection showed the library still visible after Edit Desktop. Window-server metadata confirmed the library at level 4 above editable prints at level 3; Done restored the library to level 0 and prints to desktop level. Wallpaper and locked prints occupy separate levels, so background focus cannot cover the pictures. The automation server rejects pointer drags on borderless desktop panels (`noWindowsAvailable` / `windowNotFoundAtPosition`); physical pointer dragging is therefore not claimed from this run. Direct AppKit event checks cover the changed drag handling.

The existing 0.9.0 release evidence below remains applicable to unchanged importer, model, schedule, wallpaper synchronization and distribution inputs. This focused correction does not rebuild a universal DMG or replace the published release assets.

The local `/Applications/Cork.app` is build 17, with a matching arm64 executable and a valid deep signature. Its live board remained exactly at revision 339 with 34 items and the same desktop settings. Login registration is enabled, and both custom global shortcuts remain registered. The installed wallpaper accepted **⌘L**; Edit Desktop kept the library above all 26 visible prints, and Done restored normal layers. After the user's Touch ID approval on 31 October 2026, Cork's existing system permission switch was On and its live runtime confirmed Accessibility access, active trackpad contact monitoring and both registered shortcuts. The exact board and desktop settings remained unchanged. This check does not establish physical third-finger gesture recognition or actual cross-app minimization. Screen Recording remains a separate unavailable permission.

## 0.9.0 release — 30 October 2026

The importer, onboarding, visible two-colour controls, favourites and periodic randomization were built in Swift 6 and verified on the existing Apple silicon/macOS host. Both arm64 and x86_64 release slices compile and link without warnings. Intel hardware and macOS 14 runtime behavior were not exercised on this host.

- **65/65 core checks, 12/12 importer checks and 11/11 wallpaper synchronization checks passed.** New coverage includes favourite recovery/mood restoration and preserved global preferences; default-off schedules, local calendar/DST, deferral/cancellation/coalescing; large-library diversity, stable source IDs across renames and rare second-colour retention; cookie consent/domain/path scoping, read-only browser SQLite, denied keys, Chromium v10/v24 domain integrity, resource pagination, incomplete feeds, rate limits, private reviews, actual colour measurement, removed images and lost-commit reconciliation.
- Native welcome → bundled importer → resume review → remove/restore → add eight images → create collage passed with an isolated data directory/socket. Cork saved every imported image's measured colour profile. Fixture imports did not use the live user's board.
- The real Chrome profile-folder picker and scoped cookie connection authenticated a Pinterest account and listed multiple pages of boards. A two-board review returned 20 + 10 images. A separate **All** review returned all ten available images from a small board, with an explicit skipped-pin notice. These metadata checks did not download a full-resolution archive. Review files contained no credentials. Disconnect cleared the session and retained Resume Review.
- Foreground inspection confirmed board/checkbox/count labels, main-window keyboard selection of Blue + Yellow, accent choice, favourite Save with its initial name, exact favourite item restoration, and native light/dark surfaces. A one-minute schedule produced and persisted a new scene, advanced its next deadline, and was returned to Off. This run adds no physical gesture or cross-app minimization claim.
- Installed `/Applications/Cork.app` is **0.9.0 build 16**. All three executable hashes match the packaged release. Installation preserved the latest 34-item board, revision and desktop settings exactly, along with 449 existing collection images, 57 wallpapers and enabled login registration. The previous installed bundle was retained for rollback.
- The universal DMG contains only Cork (including its importer/MCP bridge), the AGPL license, Applications link and install note. Every executable has both architecture slices. Strict deep signatures, DMG integrity and SHA-256 checks passed. The download is about 6 MB. It is ad hoc signed, **not Developer ID signed or notarized**. Personal Pinterest media and fixture state are excluded.

Local Accessibility refresh completed after the user authenticated with Touch ID. The stale Cork entry was confirmed absent, then the exact `/Applications/Cork.app` bundle was re-added and its switch confirmed On. The running app reported `accessibility_allowed: true`, `gesture_monitoring: true`, both shortcuts registered and login enabled; the 34-item board remained at revision 339. No rebuild or TCC database edit was involved. Screen Recording remains unavailable, so no successful live desktop capture is claimed. Physical gesture recognition and cross-app minimization were not exercised by this permission check. Importing, arranging, colours, favourites and schedules need neither permission.

The records below describe earlier feature verification and permission states.

Cork **0.6.0, build 12**, verified 28 October 2026 on Apple Silicon, macOS 27.2 (26B118), Swift 6.3.2 and the Command Line Tools macOS 26.5 SDK. Deployment target remains macOS 14+. No global Xcode selection or license changes were made.

## Historical 0.6.0 verdict

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

## 0.7.0 — menu-bar wallpaper and paired moods

Focused native Build/Fix scope on 2026-10-30, using Swift 6.3.2 and the installed macOS 26.5 SDK. A warning-free incremental release build installed as `/Applications/Cork.app`, version 0.7.0 build 14; strict deep signature validation passed. The earlier evidence above remains historical rather than a claim about the present catalogue or permissions.

- **53/53 core checks passed**, including paired-palette migration/validation, balanced visible colour area, cross-board variety, unrelated-background rejection and preserved Fill Empty anchors. Existing single-family blue/pink regression checks passed.
- **11/11 focused native wallpaper checks passed** with an injected workspace: exact original display options, restart recovery, external changes, interrupted writes, failed restoration, disconnected displays and bounded recovery storage. No unchanged native-boundary code was retested solely for the later palette addition.
- Live native state matched Cork's managed wallpaper. Selecting System restored the original native URL, scaling, clipping and fill. An immediate refresh while the System image was still loading completed correctly; Undo restored Cork's image with every pre-existing item and catalogue unchanged. Orderly quit also restored the original native state and cleared the recovery journal. These checks use actual `NSWorkspace` state, not a menu-bar pixel capture.
- Eight new paired photo groups were merged through the running app, bringing the private library to **449 photos, 57 wallpapers and 22 eligible moods**. Only 178 photos' mood memberships changed; existing metadata, source links, asset names and all earlier memberships were preserved. The import did not change the wall or add media files. No new downloads were needed.
- **24 actual-library compositions passed**, three seeds for each new mood. The smaller colour family occupied 39.3–49.4% of photo area, with 9–13 source boards per scene. Every selected wallpaper met this display's real pixel/crop requirements and matched a represented family. All eight representative compositions were inspected using the production print renderer; these offscreen renders are not desktop captures.
- A live **Blue & butter** roll produced the exact reviewed photo selection and geometry, selected a native-resolution blue lake wallpaper and reported native synchronization without a loading error. Existing notes, hidden widgets and kept content retained their positions and state. The new scene remains on the desktop and supports Undo.
- Native Settings showed **449 photos · 22 moods**, all eight new choices in both relevant menus, the current paired swatches and the unchanged automatic matching preferences. The rendered Settings surface retained readable native controls and the enabled login setting. The saved scene matched the live photo geometry, wallpaper and paired palette exactly.

Accessibility refresh for the final installed signature is complete. After the user authenticated with Touch ID, System Settings showed Cork absent; the exact `/Applications/Cork.app` was re-added with its switch on. The running app reported Accessibility allowed, active contact monitoring with 1,201 received frames, and both global shortcuts registered without errors. The saved scene, revision 157, catalogue and native wallpaper synchronization remained unchanged; login stayed enabled. Screen Recording remains a separate unverified permission, so desktop screenshot capture and direct menu-bar pixel verification are not claimed. Physical gesture recognition/minimize-all, additional monitors, video playback and older OS versions were not repeated for this focused change.

Native verdict: **ACCEPT** for the wallpaper correction, paired-mood addition and existing Accessibility refresh. The installed behavior passed the applicable checks above, and the system permission gate is resolved.

## 0.8.0 — selectable colour combinations

Focused native Build scope on 2026-10-30. A warning-free release build installed as `/Applications/Cork.app`, version 0.8.0 build 15, with strict deep signature verification. No new runtime dependencies or downloaded media were introduced.

- **59/59 core checks passed.** New cases measure real strong/accent pixel fractions, validate all 78 distinct pairs of the 13 families, preserve legacy data and saved choices, select across mood boundaries, balance measured colour area, preserve Fill Empty anchors/Undo, reject wrong-family or undersized wallpapers, and backfill caches without changing metadata or media. Missing media leaves the previous cache untouched.
- All **449 photos and 57 wallpapers** were classified locally by the running app. Saved profiles exactly matched an independent read-only pass. Removing the new profile fields left the earlier catalogues unchanged. Earlier curated memberships, source descriptions, palettes and managed assets were preserved. The previously disliked monochrome beach background was excluded from future automatic selection through the existing metadata import, without deleting its media.
- **12 real-library compositions passed:** three seeds each for Blue + Yellow, Red + Violet, Black + White and adjacent Blue + Teal. Both selected families contributed 35.6–44.9% for the smaller share of measured coloured area. Every sampled scene retained board diversity, the source cap, fixed content and a suitable native-resolution wallpaper. Blue + Yellow and Red + Violet were inspected with the production renderer. These renders are not screen captures or a promise that every possible combination has sufficient photos.
- Native Settings exposed both labelled colour selectors, excluded duplicate choices, showed availability counts and offered **Roll These Colours**. Blue + Yellow had 105 matching strong-colour photos. Red + Violet had 33; enabling accents expanded that pool to 40. The native controls and their rendered labels were inspected in context.
- The native Blue + Yellow button and a Red + Violet MCP roll both completed with matching native wallpaper. Their measured smaller-family shares were 41.3% and 44.7%. Undo restored the scene, and test-only preference changes were undone. The user's current Sage & lilac composition, note text, hidden toys, geometry and prior settings remained intact; only the increasing revision changed.
- A real app restart retained the entire scene at revision 174. Both classification files kept exactly the same bytes and modification times, proving the saved caches were reused. The app reported 449/449 photos and 57/57 wallpapers classified, no analysis error, synchronized native wallpaper and enabled login launch.
- Accessibility was refreshed for the exact final Applications bundle. The running app reported AX access, active trackpad monitoring and both global shortcuts registered. Physical gesture recognition/minimize-all was not re-exercised. Existing Screen Recording and broader platform limitations remain separate from this feature.

Native verdict: **ACCEPT** for custom colour pairs, measured classifications, saved cache reuse and the final installed permission refresh.
