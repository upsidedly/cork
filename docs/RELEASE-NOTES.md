# Cork 0.11.0

Keep Pinterest boards fresh daily, and let a video take over the whole desktop collage.

- **Daily Pinterest sync:** select boards in the bundled importer, then choose **Keep Selected Boards Fresh Daily…**. New pins receive local colour metadata and join your collection without rebuilding Cork or changing the current collage.
- **Explicit recurring access:** daily sync starts off and asks for separate consent. Only a read-only browser-profile bookmark is remembered; Pinterest cookies and browser keys are never saved. Background authentication cannot open password prompts. Pause, Check Now and Remove Connection are available under **Daily Sync…**.
- **Bounded storage:** 10 new images a day by default, configurable to 5 or 20; a 32 MB daily image budget and 2 GB free-space floor. The first check records a latest-100 baseline per board without downloading older pins. Existing and rejected pins stay out of the queue, and selected sources take turns.
- **Video takeover:** double-click a video print to expand it above every Cork print, note and widget on that display. Double-click again or press Escape to restore the collage and previous background. Covered playback pauses. App windows remain above the wallpaper, and saved geometry stays intact.
- **Wallpaper keyboard focus:** clicking Cork's wallpaper keeps ordinary menu commands available, including Command-R, Command-Z and Command-L, across wallpaper replacement.

## Install

Download `Cork-0.11.0-universal.dmg` and drag Cork into Applications. Requires macOS 14+, Apple silicon or Intel. The Pinterest importer and local MCP bridge are included. Personal media and account data are not bundled.

The community build is **ad hoc signed and not notarized**. Follow [Apple's Open Anyway instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac) if macOS blocks first launch. An existing Accessibility entry may need refreshing after updating; that permission is needed for minimize-all and the trackpad gesture, not this video interaction.

Updates preserve `~/Library/Application Support/Cork`. The `.sha256` file verifies the DMG. Native build and interaction evidence is in [VERIFICATION.md](https://github.com/upsidedly/cork/blob/v0.11.0/docs/VERIFICATION.md). AGPL-3.0-or-later.
