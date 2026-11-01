# Cork 0.10.1

Double-click a video print to zoom it into the wallpaper. Double-click the wallpaper again to return it.

- The print returns to the same place and the previous background returns with it. The effect is temporary and reuses the existing clip; your saved layout and wallpaper stay intact.
- Return opens a focused video; Escape brings it back. VoiceOver actions expose both commands. Reduce Motion removes the zoom while preserving explicitly requested playback.
- An existing video wallpaper pauses during the effect and resumes its original player afterwards. Sleep, inactive sessions and quitting release or pause playback appropriately. Scheduled rolls wait while the preview is open.
- Moving, hiding or removing the source, editing the desktop, changing displays or selecting another wallpaper cancels the stale preview. Rapid double-clicks can reverse the transition.

## Install

Download `Cork-0.10.1-universal.dmg` and drag Cork into Applications. Requires macOS 14+, Apple silicon or Intel. Pinterest importing, video prints, colour matching, favourites, schedules and the local MCP bridge remain included. Personal media and account data are not bundled.

The community build is **ad hoc signed and not notarized**. Follow [Apple's Open Anyway instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac) if macOS blocks first launch. An existing Accessibility entry may need refreshing after updating; that permission is needed for minimize-all and the trackpad gesture, not this video interaction.

Updates preserve `~/Library/Application Support/Cork`. The `.sha256` file verifies the DMG. Native build and interaction evidence is in [VERIFICATION.md](https://github.com/upsidedly/cork/blob/v0.10.1/docs/VERIFICATION.md). AGPL-3.0-or-later.
