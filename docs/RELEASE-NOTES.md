# Cork 0.10.0

Video prints for your desktop wall.

- Add local MP4, MOV or M4V files alongside images. Tape, Pushpin, Polaroid and Frame keep a static cover until hovered, then play a muted loop. Moving away restores the still.
- Click a video and use Space to play or pause, or Escape to stop. Reduce Motion disables automatic hover playback while preserving keyboard and accessibility actions.
- Cork measures five spread-out frames before including a video in a matching collage. Covers determine resting colour balance; motion samples also constrain the selected colours. Videos participate in rolls, Fill Empty, coordinate reflow, display adaptation, visibility and favourites.
- The MCP adds `cork_add_video`. Collection manifests accept `kind: "video"`; optional `removeIDs` excludes selected entries from future rolls while retaining media and saved scenes. Failed imports roll back their new files and existing copies are reused.
- The Pinterest importer, colour choices, favourites, schedules and Swingset widgets remain included. Cork itself does not connect to TikTok; an explicitly authorized external connector can supply downloaded local clips.

## Install

Download `Cork-0.10.0-universal.dmg`, open it, and drag Cork into Applications. Requires macOS 14+, Apple silicon or Intel. Cork Importer is included. Personal photos, videos and account data are not bundled.

**Signing:** this community build is ad hoc signed, not Developer ID signed or notarized. macOS may require **Privacy & Security → Open Anyway** for first launch. See [Apple's instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac). Existing Accessibility entries may need refreshing after an update; this permission is needed for minimize-all and the trackpad gesture, not video prints. Screen Recording remains optional for requested desktop captures.

Videos may be up to 200 MB and ten minutes. Media stays local and the app loads no video decoder for a resting print. Image and video rights remain with their owners. Source code: AGPL-3.0-or-later.

The `.sha256` file provides the DMG checksum. Updating preserves `~/Library/Application Support/Cork`. Focused build, playback, colour and persistence evidence is in [VERIFICATION.md](https://github.com/upsidedly/cork/blob/v0.10.0/docs/VERIFICATION.md).
