# Cork user guide

For installation and a quick overview, see the [README](../README.md).

## Start with your Pinterest

Choose **Import from Pinterest…** in Cork's toolbar or File menu. The bundled importer explains its browser-cookie access before connecting, then lets you choose boards and **20 / 50 / 100 / 150 / 200 / All** images per board. Remove unwanted pictures in the review gallery and choose **Add to Cork**. Full instructions, supported browsers and recovery are in the [importer guide](IMPORTER.md). A fresh install shows a welcome screen; file hiding and login launch are optional.

For future pins, select boards and choose **Keep Selected Boards Fresh Daily…**. Read and approve the separate recurring-access disclosure, set the time and daily limit, then enable sync. The first check records a baseline without downloading old pins. Later checks add new, colour-classified images to the library; your current collage stays put. Use the importer's **Daily Sync…** button to check status, pause, check now or remove the connection. See [daily sync limits and privacy](IMPORTER.md#daily-pinterest-sync).

**Choose two colours** stays at the top of Cork's main window. Choose a **Dominant** colour on the left and a **Secondary** colour on the right; either can be **Random**. The dominant colour guides the wallpaper and larger colour share in the collage. The **star** saves named favourite corkboards; Load restores their layout, mood, notes, wallpaper and colour choices while keeping global settings. The **clock** enables minute/hour/day/week, morning/evening or custom automatic rolls. It starts Off, waits during editing and catches up once after sleep. Cork must be running.

## Put something on the wall

Open Cork from the menu bar. Choose **Add Images or Videos…**, paste an image, or drop media files into the library. Cork keeps its own local copy, so moving the original file does not break your wall.

Select an image and choose **Tape**, **Pushpin**, **Polaroid**, or **Frame**. An optional title becomes the Polaroid caption in marker lettering. Leave it blank for an unmarked print. Images and videos keep their aspect ratio inside the print.

A video looks like a still print until hovered, then loops silently. Moving away restores the still and releases playback. Click a video and press **Space** to play or pause, or **Escape** to stop. With Reduce Motion, only explicit keyboard or accessibility playback runs. MP4, MOV and M4V files may be up to 200 MB and ten minutes; import creates an owned copy and a static cover.

Video covers participate in layout and dominant-colour balance. Five spread-out frames are measured locally, and every sample must fit the requested colour pair before a video joins a matching roll. This is a bounded sample of the clip, not semantic analysis of every frame.

Double-click the image area of a locked video print to expand it into the wallpaper. It covers all Cork prints, notes and widgets on that display; ordinary app windows remain above it. Double-click the wallpaper again to bring the collage back, or use **Escape**. A focused video supports **Return** and the **Use video as wallpaper** accessibility action. This temporary view reuses the local clip, leaves the layout and saved wallpaper unchanged, and pauses covered widgets, print playback and the previous video wallpaper until you return. The native wallpaper uses the video cover so the menu bar follows it too. Editing, moving/hiding/removing the source, choosing another wallpaper or quitting ends the view. Automatic rolls wait while it is open. Reduce Motion makes the transition immediate while keeping explicitly requested playback.

Choose **New Note** for editable text. **Flat** uses solid paper; **Sticky** adds shading and a curled corner. Choose a paper color, write your text, and select **Save Note**. Titles are optional.

Each note has an **Include in layout** checkbox. Keep it checked to leave room for that note when filling or rolling the wall. Untick it to let pictures fill behind the note: it stays in its chosen position, above photos added by later rolls too. The choice works with both Flat and Sticky notes, saves automatically and supports Undo. Existing notes start checked.

Enable **Match collage colours** on an individual note to tint its paper from the visible photos. Cork keeps the tint pale for readable text and updates it with scene changes. Turn the checkbox off to return to the note’s manual paper colour.

## Arrange it

Choose **Edit Desktop** to move items directly on the screen. Drag a print or note to position it; drag its lower-right handle to resize it. The library has size and angle controls, plus exact position and dimensions under **Position & dimensions**. X and Y each have a slider beside their numeric field. Moving or resizing a participating image or note holds that item at its new position and reflows the same photos around it, preserving their identities, treatments and angles. Moving an overlay note leaves the photos alone.

Click Cork's wallpaper to focus its keyboard shortcuts without opening the library: **⌘R** rolls, **⌘Z** undoes, and **⌘L** opens the library. The library stays above desktop items while editing; **Done** returns it to its normal window level. Clicking or dragging an editable print also focuses Cork.

Choose **Arrange → Fill Space** to repack existing prints into the largest free rectangles. Choose **Fill Empty** to keep every existing item in place and add matching photos around it. Enable **Keep in place** on a selected image to protect it during a dice roll or automatic arrangement too. Notes stay put. The widget corner is reserved while widgets are visible; hiding widgets frees that area. **Gallery**, **Grid**, and **Collage** remain available. **Done** or **Esc** locks it again. Locked photos and notes sit below application windows and let mouse clicks pass through to the desktop. Video prints accept hover and keyboard playback; interactive widgets remain playable. Edit mode temporarily brings items forward for moving and resizing.

| Key | Action |
| --- | --- |
| ⌘L | Open the library while Cork is active |
| ⌘O | Add images or videos while Cork is active |
| ⌘N | New note while Cork is active |
| ⌘R | Roll a new wall from the rotation collection |
| ⌃⌥⌘R | Randomize from any app; configurable in Settings |
| ⌃⌥⌘M | Minimize application windows globally; configurable in Settings |
| Arrow keys | Move the focused desktop item 1 point in Edit Desktop |
| Shift + arrow keys | Move 10 points |
| [ / ] | Rotate the focused desktop item 1°; Shift changes 10° |
| Delete | Remove the focused desktop item |
| Esc | Finish desktop editing |
| ⌘Z / ⇧⌘Z | Undo / redo; text editors keep their normal editing undo |

Changes save automatically, except note text awaiting **Save Note** and numeric fields awaiting Return. Undo covers the current app session. Removing an item leaves the original file and Cork's image copy intact.

Each library row has an **eye** button. Hide an item to repack the wall without it; Show brings it back into the layout. Hidden items, their media and state stay saved, and visibility changes support Undo.

Changing your display’s resolution or “More Space” setting refits the current wall automatically after a short notification debounce. A smaller canvas keeps existing items on screen. A larger canvas preserves the existing layout and adds photos from the collection into the new space, using the current mood and colour settings. Hidden items and other displays stay saved.

## Desktop widgets

Open [Swingset](https://github.com/Upsidedly/swingset), pick one of its ten fidgets, and click **Add to Cork**. Cork registers the local package, places the toy around fixed items, and reflows the existing photos around it. New toys choose separate space instead of stacking on an earlier toy. You can quit Swingset afterward; Cork owns a copy. Each widget has independent saved state.

For other apps, use **Settings → Widgets → Register Widget Provider…**, then **Add Widget**. The live library preview also lets you play, move, resize, hide or remove a widget. There is a local registration system; no hosted marketplace is required. See the [widget contract and runnable example](WIDGETS.md).

## Make the desktop yours

**Settings → Hide desktop files while Cork runs** hides file and folder icons from view. Everything stays in your Desktop folder, available through **Open Desktop Folder** or Finder. Icons return when Cork quits. Cork draws its own wallpaper above the icons; it does not move files, change Finder preferences, or restart Finder. While hidden, clicks on the wallpaper cannot select the covered files.

**Hide Apple widgets while Cork runs** covers desktop widgets and lets new layouts use their space. It is independent of file hiding. Quitting Cork reveals the widgets again; their contents and macOS settings are retained.

Under **Wallpaper**, keep **System** or choose a local **Image** or **Video**. Cork copies the media into its own storage. Video loops without sound, with a pause control, and pauses during display sleep, an inactive user session, or Reduce Motion. Choosing **System** returns to your Mac's original wallpaper. Custom wallpaper is shown while Cork runs.

The native macOS wallpaper is synchronized with Cork's image, or a video's saved poster frame, so the menu bar takes its colour from the same scene. The original image and scaling options are saved before changing them and restored on **System** or quit. A wallpaper changed outside Cork is preserved on quit. A small local recovery record protects restoration after an interrupted update.

The wall, saved note text, layout, desktop and widget visibility, palette preferences, wallpaper, video pause choice, shortcuts, and default image style restore on the next launch. Enable **Open Cork at login** in Settings after installing the app in Applications. macOS may ask you to approve it in Login Items settings; Cork shows the actual registration state.

## Minimize every window

Press **⌃⌥⌘M** from any app, or choose **Minimize All Windows** in Cork. Windows go to the Dock and stay minimized until you restore them. Pressing again leaves them minimized. Full-screen, modal or nonresponsive windows may not support minimization.

Change the shortcut in **Settings → Minimize all windows**: click the current combination and press your choice. Include Command, Option or Control. Escape or leaving the window cancels; **Reset** restores the default. A conflicting shortcut keeps your previous choice. The shortcut and gesture toggles restore after a restart.

For the trackpad gesture, hold **two fingers still**, then swipe **down with a third finger**. Lift all fingers before repeating. Ordinary two-finger scrolling and moving all three fingers together are rejected. The gesture uses a private macOS trackpad API; availability can change with macOS updates, while the keyboard shortcut remains independent.

Enable Cork in **System Settings → Privacy & Security → Accessibility** to let it minimize windows in other apps. Cork opens that page from Settings; it cannot grant itself access. The raw gesture reader stays off until access is enabled, and pauses during display sleep or an inactive session. Finger positions are never saved.

## Roll another wall

The **dice** button in the library, **Roll Wall** in the menu bar, **⌘R**, or the global **⌃⌥⌘R** picks a new wall from your local photo collection. Change the global binding under **Settings → Quick randomize**. Each roll stays within one curated visual mood, mixes Pinterest boards and subjects, chooses photo aspect ratios to greedily fill the free rectangles, favors photos you are not currently showing, and mixes Tape, Pushpin, Polaroid, and Frame prints. When a mood has enough sources, rolls start with four different boards and limit each board to about 40% of the wall. The number and sizes adapt to the available space, up to twenty new photos. New captions are blank. Notes, kept images and other displays stay put; **⌘Z** restores the previous scene, including its wallpaper.

Choose a mood under **Settings → Rotation → Next wall**, or leave **Surprise me** selected to switch moods. A mood needs at least eight photos. The current wall and next-roll preference are saved; rolling needs no network or screen access. Nothing changes on a timer.

**Match image colours** coordinates photos with a shared palette. **Colour palette** offers twenty-two curated choices, or derives one from the mood and retained images. **Match wallpaper to palette** chooses a compatible background before fitting the photos. Automatic wallpapers must cover the display at its native pixel resolution and retain at least 60% of the source when cropped. If none fits, Cork keeps the current background. Choosing a wallpaper manually turns automatic wallpaper matching off; enable it again when you want coordinated scenes.

Eight palettes use two major colours: **Blue & butter**, **Teal & rust**, **Forest & rose**, **Cobalt & vermilion**, **Plum & ochre**, **Sage & lilac**, **Olive & coral**, and **Espresso & ice**. A mood with the matching ID uses its pair automatically. Cork balances the visible area of both families, including kept prints, while still mixing boards, treatments and aspect ratios. A paired palette needs photos in both families; if a chosen mood lacks one, choose another mood or disable image colour matching. Wallpaper follows one of the families actually present, or uses a quiet neutral; opposing colours are not averaged into an unrelated hue. Paired palettes are built in, while the photo groups themselves come from your imported collection.

The two main-window pickers also appear under **Colour palette → Choose two colours**. Fixed choices come from Red, Orange, Yellow, Green, Teal, Blue, Violet, Pink, Brown, Cream, Black, Grey and White; choose different families for the two fixed slots. **Blue + Random** keeps blue dominant and changes the secondary colour. **Random + Blue** keeps blue secondary and changes the dominant colour. **Random + Random** chooses a fresh pair. The resolved colours appear beneath the pickers. Random uses colours with enough matching images and prefers a suitable native-size wallpaper when available; alternatives avoid repeating the previous random choices when possible.

This mode searches the entire classified collection; the mood picker is inactive until you return to a preset or automatic palette. **Roll These Colours**, the ordinary dice, shortcuts and scheduled rolls use the same saved choices. Favourites retain both the exact scene and which slots are Random. **Fill Empty** and display refits retain the current resolved pair instead of choosing new random colours.

**Strong colours** requires a chosen family to cover at least 18% of a photo. **Include accents** also accepts coverage from 4%. Fixed-colour counts show what is available before rolling. Grey paper or white margins cannot excuse a strongly unrelated coloured subject. Photos can belong to several families, with measured proportions counting toward layout balance. Custom layouts favor the dominant colour while preserving source variety, aspect ratios and kept prints. Wallpaper follows the dominant family; a quiet neutral carrying that colour can serve as a fallback. If no suitable native-size wallpaper exists, Cork keeps the current background and reports the missing match in palette settings.

Colour analysis runs locally in the background after upgrading an older library. Existing scenes remain visible; custom rolls wait for analysis. Future imports are classified immediately. The cache survives restart, and **Photo details** shows each significant family, its strong/accent label and coverage percentage. Analysis failure preserves the saved wall and offers **Retry Colour Analysis**. Nothing is uploaded and no extra media copies are made.

**Fill Empty** uses those same colour controls while preserving every existing print's position, size, angle and treatment. It can infer the palette from those images or follow your selected palette. It adds photos only where decorated prints fit. **Arrange → Fill Space** instead moves the existing prints without adding photos.

Before saving a scene, Cork checks the wallpaper's dominant hue against the photos actually selected. A small accent or shared grey swatch cannot justify a pink/purple background for a mostly blue wall. Matching coloured backgrounds rank ahead of neutral fallbacks; an unavailable match keeps the existing wallpaper and shows the fallback in Settings.

The collection keeps each photo's source pin, board, description, color palette, tags, and mood assignments separately from wall captions. Select a print and expand **Photo details** to inspect them. Collection photos are copied locally at up to 2048 pixels; source downloads stay where they were.

An agent can prepare a metadata manifest and use `cork_import_collection`; **Settings → Import Photo Collection…** accepts the same JSON format. See [collection format](COLLECTIONS.md). Personal Pinterest media and manifests stay in local application storage and are not bundled with Cork's source.

## Let an agent arrange it

Cork includes **`cork-mcp`**, a local stdio MCP server. In **Settings → Copy MCP Configuration**, copy the configuration for the current app location. The installed app uses:

```json
{
  "mcpServers": {
    "cork": {
      "command": "/Applications/Cork.app/Contents/MacOS/cork-mcp"
    }
  }
}
```

Add this server through your agent's MCP settings and reconnect it. The bundled server can open Cork in the background on its first tool call. It does not modify your agent configuration itself.

| Tool | Purpose |
| --- | --- |
| `cork_get_board` | Inspect items, stable IDs, revision, displays, usable bounds and screen access |
| `cork_get_widgets` | Inspect local providers and available widgets |
| `cork_register_widgets` | Copy and register a selected app’s local widget package |
| `cork_add_widget` | Add a stateful interactive widget and reflow photos around it |
| `cork_get_collection` | Inspect moods, counts, and per-photo metadata |
| `cork_import_collection` | Import local image/video prints and curated metadata without changing the wall |
| `cork_get_wallpapers` | Inspect palettes, wallpaper metadata and native-resolution eligibility |
| `cork_import_wallpapers` | Import selected large local wallpapers and provenance |
| `cork_roll_wall` | Roll a saved, undoable palette, wallpaper and photo composition |
| `cork_fill_empty` | Keep existing items and fill the remaining space, optionally matching colours |
| `cork_add_image` | Import a selected local image, with optional source URL |
| `cork_add_video` | Import a selected local MP4/MOV/M4V as a still print with muted hover playback |
| `cork_add_note` | Create a Flat or Sticky text note |
| `cork_update_items` | Move, resize, style, hide/show, recolour, edit notes or widget state, or keep images in place atomically |
| `cork_arrange` | Lay out all or selected items on one display |
| `cork_remove_items` | Remove items, with undo |
| `cork_undo` | Undo the latest saved change |
| `cork_set_edit_mode` | Enable or finish manual editing |
| `cork_set_desktop` | Save file/widget visibility, scene palette, image/video wallpaper and playback |
| `cork_set_login_item` | Enable or disable native login launch when you request it |
| `cork_set_desktop_controls` | Save global minimize/randomize shortcuts and the trackpad gesture preference |
| `cork_minimize_all_windows` | Minimize application windows when requested; requires Accessibility |
| `cork_screenshot_desktop` | Return a desktop PNG as an MCP image and a local file |

For Pinterest, the agent uses the **Pinterest plugin** to find and download selected pins, then passes the returned local paths to `cork_add_image`. Cork does not need Pinterest credentials. An authorized TikTok connector can similarly download selected clips for `cork_add_video` or a collection manifest with `kind: "video"`; Cork itself makes no TikTok requests. A useful request is: “Download these pins, put them on my Cork wall, arrange them around the wallpaper, and show me the desktop.”

Agent coordinates start at the **upper-left of each display, in logical points**. Width and height include the decoration; rotation is clockwise. Screenshots report their pixel-to-point scale. Batch edits and arrangement accept `expected_revision` so a stale agent cannot silently overwrite your newer manual layout.

## Screen access and privacy

Screen Recording is needed only for desktop screenshots. Open **Settings → Allow Screen Recording**, enable Cork in System Settings, and relaunch if macOS asks. Importing and arranging items need no screen access or Accessibility permission. Minimizing other apps requires Accessibility; Cork never enables it automatically.

macOS may separately ask before Cork reads imports from Desktop or Downloads. The native file picker grants access to the files you choose. Ad hoc app rebuilds can invalidate earlier file-folder and Screen Recording approvals; local collection rolls continue to use Cork's own stored copies.

Screenshot **desktop** mode excludes other apps and Cork's library/controls. **visible** mode captures what is on screen, including other applications. Wallpaper and desktop icons may appear in either. Captures are saved locally and returned to the requesting MCP client; that client controls how it uses them. Cork does not upload anything.

Images, notes, wallpapers, the board and captures live in `~/Library/Application Support/Cork`. The board is atomically saved with a previous-save backup. The local control socket is restricted to your user account. There is no network listener, account, subscription, telemetry or built-in web scraper. Imports accept PNG, JPEG and other image formats supported by macOS; images are normalized to PNG at up to 4096 pixels. Video wallpaper accepts playable local movies up to 2 GB. A board supports up to 500 items, including up to 20 interactive widgets. Widget packages have network and outside-file access blocked and expose only a small local state/feedback bridge.
