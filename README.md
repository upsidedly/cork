<p align="center">
  <img src="docs/assets/cork-icon.png" width="96" height="96" alt="Cork icon">
</p>
<h1 align="center">Cork</h1>
<p align="center">A wall for your Mac.</p>
<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-242424?logo=apple&amp;logoColor=white" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&amp;logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/Privacy-Local_only-555555" alt="Local only">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-AGPL--3.0--or--later-555555" alt="GNU AGPL version 3 or later"></a>
</p>

Cork puts posters, photos and notes on your desktop. Tape up a print, pin a photo, or leave a sticky beside it. Roll a new collage when you want a change. It shares a monochrome style with [Tuck](https://github.com/Upsidedly/tuck), [Snap](https://github.com/Upsidedly/snap) and [Cell](https://github.com/Upsidedly/cell).

<p align="center">
  <img src="docs/assets/cork-treatments.png" alt="Tape, Pushpin, Polaroid, Frame, Flat and Sticky treatments, shown with original sample artwork">
</p>

## Put something on the wall

Open Cork from the menu bar. Choose **Add Images…**, paste an image, or drop files into the library. Pick **Tape**, **Pushpin**, **Polaroid** or **Frame**. Cork keeps a local copy and preserves the image's proportions. Polaroid captions are optional and use marker lettering.

Choose **New Note** for editable text on **Flat** paper or a shaded **Sticky**. Check **Include in layout** to reserve its space, or untick it to float the note over your pictures. **Match collage colours** tints the paper to suit the visible photos.

Choose **Edit Desktop** to drag, resize and rotate items. The library also has X/Y sliders and exact dimensions. An **eye** button hides an item and repacks the wall around it. **Keep in place** protects a print during future rolls. Finish with **Done** or **Esc**.

## Roll another wall

Click the **dice**, press **⌘R**, or use **⌃⌥⌘R** from any app. Cork picks from your saved photo collection, mixes source boards and print styles, and fits images into the free rectangles. Notes and kept prints stay put. **⌘Z** restores the previous scene, including its wallpaper.

Choose a mood in **Settings → Rotation**, or leave **Surprise me** selected. Colour matching uses fourteen built-in palettes. Automatic wallpapers must fit your display at native resolution and match the selected photos. You can turn either kind of matching off.

**Fill Empty** adds pictures around the items you have placed. **Arrange → Fill Space** repacks the existing prints. Changing your display size refits the wall and can fill newly available space.

Import a collection through Settings or let an agent prepare one using the [collection format](docs/COLLECTIONS.md). Moods are curated image groups; Cork uses their saved colours, proportions and source metadata to compose each wall. A fresh installation starts with an empty photo and wallpaper library. Rolls work offline after import.

## Make the desktop yours

In Settings, hide desktop file icons, hide Apple widgets, choose an image or looping video wallpaper, and enable **Open Cork at login**. Hiding files changes their visibility while Cork runs; everything stays in your Desktop folder. Quitting reveals the original desktop again.

Prints, notes, wallpaper and settings restore when you reopen Cork. Saved note text uses **Save Note**; other layout changes save automatically.

Press **⌃⌥⌘M** to minimize application windows to the Dock. They stay minimized until you restore them. Change this shortcut in Settings, or enable the gesture: hold two fingers still and swipe down with a third. Minimizing other apps requires Accessibility permission.

## Add desktop toys

[Swingset](https://github.com/Upsidedly/swingset) supplies ten fidget toys. Choose one there and click **Add to Cork**. Cork keeps its own widget copy and saved state, so you can quit Swingset afterward.

Other apps can register local HTML, CSS and JavaScript widget packages through **Settings → Widgets**. See the [widget guide and working example](docs/WIDGETS.md).

## Let an agent arrange it

Cork includes a local MCP server. Copy its configuration from Settings, or add:

```json
{
  "mcpServers": {
    "cork": {
      "command": "/Applications/Cork.app/Contents/MacOS/cork-mcp"
    }
  }
}
```

The agent can add images and notes, import collections, arrange or roll the wall, manage widgets and request desktop screenshots. For Pinterest, your agent's **Pinterest plugin** finds and downloads pins, then passes local files and curated metadata to Cork. Pinterest browsing and curation happen outside the app.

See the [user guide](docs/USAGE.md#let-an-agent-arrange-it) for tools, coordinates and screenshot modes.

## Install from source

Use macOS 14 or later with Swift 6 and a compatible macOS SDK.

```sh
git clone https://github.com/Upsidedly/cork.git
cd cork
./scripts/install.sh
open /Applications/Cork.app
```

Quit Cork before updating it. The installer builds and signs the app locally, backs up an earlier installation and leaves your wall intact. There is no notarized download yet. After a rebuild, macOS may require you to remove and re-add Cork's permission entries.

## Compatibility and privacy

Accessibility is needed for minimizing other apps. Screen Recording is needed for requested desktop screenshots; captures are saved locally and returned to the requesting MCP client. Adding pictures, arranging the wall and rolling collections need neither permission.

The optional trackpad gesture uses a private macOS API and can be affected by system updates. The keyboard shortcut remains available independently of that API.

Cork needs no account and has no network service, telemetry or built-in Pinterest scraper. Images, notes, collections and settings stay in `~/Library/Application Support/Cork`. Personal Pinterest media is not included in this repository. Widget packages are restricted to their local files and cannot access the network.

## Development

Build with `./scripts/build.sh`. Run the core checks with `./scripts/check.sh`. Set `CORK_SDK` to use another compatible SDK without changing global Xcode settings.

See the [user guide](docs/USAGE.md), [development notes](docs/DEVELOPMENT.md), [source references](docs/RESEARCH.md) and [verification record](docs/VERIFICATION.md).

## License

Copyright © 2026 Upsidedly. Cork is free software under the **GNU Affero General Public License, version 3 or later**. See [LICENSE](LICENSE) and [COPYRIGHT](COPYRIGHT).
