# Rotation collections

A collection is a local pool of photos, separate from the visible wall. Cork imports the selected files into `Images/` and saves their metadata in `collection.json`, with `collection.previous.json` for recovery. Metadata stays available when a wall caption is blank.

Import through Settings or `cork_import_collection({"path":"/absolute/path/manifest.json"})`. For MCP, use batches of about 20 photos so large conversions stay within transport timeouts. Each manifest merges into the existing collection by stable photo ID. An existing ID must keep its source URL; metadata can be updated without copying the image again. Inspect `cork_get_collection` before resuming an import whose response was lost. No mutation is retried automatically.

```json
{
  "schemaVersion": 1,
  "themes": [
    {
      "id": "open-air",
      "name": "Open air",
      "description": "Fresh greens, blue skies, meadows and water."
    }
  ],
  "photos": [
    {
      "id": "pinterest-pin-id",
      "path": "/absolute/path/to/downloaded-image.jpg",
      "title": "Lake light",
      "description": "A lake beside a green hillside.",
      "sourceURL": "https://www.pinterest.com/pin/123456789/",
      "sourceBoard": "nature-photography",
      "tags": ["landscape", "water", "quiet"],
      "palette": ["#365B47", "#8CBBD1", "#E7E8D9"],
      "themeIDs": ["open-air"]
    }
  ]
}
```

Supply verified local paths and source links. Cork's MCP does not download arbitrary URLs or access Pinterest credentials. The separate, consent-based [Cork Importer](IMPORTER.md) handles Pinterest browsing. Manifest import accepts 1–200 photos per batch, up to 20,000 photos and 50 themes in the collection. Source images must meet Cork's image import limits. The app normalizes its collection copies to PNG at up to 2048 pixels and records their dimensions. Source downloads are not modified.

A theme needs eight photos before it can be rolled. Theme membership is an explicit curation decision; the app does not infer artistic similarity from the source board or claim to understand an image. Use visual review to group palette, medium, mood, and subject, remove duplicate images, and exclude poor fits. Palette values are metadata, not a substitute for visual curation. Retain known source descriptions without inventing artist, place, authorship, or license claims.

`cork_roll_wall` accepts an optional theme ID, integer seed, display ID, `palette`, `colour_aware`, and expected board revision. It greedily fits up to 20 distinct new photos from one visual theme, favors photos absent from the current wall, mixes the four print treatments, and leaves all captions blank. Auto selection avoids the previous theme when alternatives exist. Randomness changes the image selection, print treatments, size, angle, and placement; a fixed seed reproduces these choices for the same inputs.

The layout reserves the upper-left while desktop widgets are visible and treats notes and kept images as obstacles. It never moves notes or replaces images on other displays. It packs maximal free rectangles rather than a fixed grid. If too little usable space remains, it returns an error. A roll is one atomic, undoable board save, including its mood, seed, palette and selected wallpaper. It uses existing local assets and needs no network or Screen Recording permission. A timer is optional and off by default; the clock button configures it.

`cork_get_collection` metadata is paginated with `offset` and `limit` (1–500, default 500). `has_more` identifies another page. Optional `ids`/`source_urls` filters accept up to 200 entries each and return the union of matches. Inspect these after any ambiguous import reply before retrying. A large library uses a seeded source/aspect sample of up to 360 candidates before packing; later rolls can sample different images. With two eligible source boards the share cap is about 60%; with three or more it is about 40%, subject to retained anchors.

`sourceBoard` is the readable source label. Optional `sourceBoardID` (up to 200 characters) provides stable grouping even when a board is renamed. Cork Importer supplies Pinterest's board identity; older manifests continue grouping by their existing labels. Keep identifiers consistent across imports. Sampling also reserves both colour families in paired layouts, including when one is rare in a large library.

`cork_fill_empty` accepts the same options and preserves all existing items. It adds one or more photos wherever they fit. Both operations use the saved scene options unless a call supplies a palette or colour override. `cork_update_items` accepts `keep_in_place` for images; a kept image survives rolls and arrangement as well as Fill Empty. Palette matching ranks dominant colours in OKLab while preserving curated mood membership and source diversity; it is not semantic image recognition.

Notes accept `include_in_layout` in `cork_add_note` and `cork_update_items`. The default is true: greedy packing reserves their footprint. False makes a note an overlay, releasing that space for pictures while keeping the note's geometry and drawing it above all photos. Fill Empty and rolls retain both kinds of notes. Other arrangements leave overlay notes unchanged; Gallery, Grid and Collage can arrange participating notes with the prints. The stored optional `includeInLayout` field preserves legacy boards and survives restart and undo.

Personal media is not licensed for redistribution by a Pinterest save. Keep private collections out of the repository and do not include them in app distribution or public demos without appropriate rights.


## Visual grouping and source variety

Assign `themeIDs` by shared palette, light, texture and atmosphere across subjects. A mood can mix a landscape, interior, guitar, drawing, street scene and car. Keep `sourceBoard` as the original Pinterest board for provenance; do not rename it to the mood. Tags such as `subject:interior`, `subject:illustration` and `medium:photography` retain the distinction between what an image depicts and how it feels.

Use several source boards per mood. Dice rolls choose four different boards first when available and cap each source at `ceil(wallPhotoCount × 0.4)`, while fitting decorated aspect ratios to free rectangles. Single-board and two-board custom collections remain usable; they cannot provide the same source variety. A mood still needs eight photos to be eligible. Imports update metadata by stable photo ID and reuse existing managed images. Renaming a mood can keep its stable ID so saved preferences continue to work.

## Wallpaper collections

Import through **Import Wallpaper Collection…** or `cork_import_wallpapers`. The separate `wallpapers.json` catalogue owns its managed JPEG copies in `Wallpapers/`; importing does not change the visible board.

```json
{
  "schemaVersion": 1,
  "wallpapers": [{
    "id": "pinterest-pin-id",
    "path": "/absolute/path/to/large-wallpaper.jpg",
    "title": "Evening paint",
    "sourceURL": "https://www.pinterest.com/pin/123456789/",
    "sourceBoard": "Original board name",
    "themeIDs": ["blue-hour", "print-shop"]
  }]
}
```

Use 1–50 entries per import and up to 100 stored wallpapers. Each source is limited to 50 MB and 100 megapixels; copies preserve orientation and normalize to JPEG at up to 8192 pixels. Cork measures pixel dimensions and dominant sRGB colours itself. Existing IDs retain their source URL and managed asset. A failed batch leaves the catalogue unchanged and removes only its uncommitted media; the previous complete catalogue supports recovery.

Automatic selection requires **both dimensions** to meet the target display's logical size multiplied by its scale, with at least 60% of the source visible after aspect-fill cropping. Cork never enlarges a small file to make it eligible. `cork_get_wallpapers` reports the twenty-two palettes, current palette, catalogue and display-ready count. Search results can use an honest provenance label such as "Pinterest discovery" rather than inventing a source board. Keep downloaded personal wallpaper media and its manifests private alongside photo collections.

## Paired colour moods

The built-in pairs are `blue-butter`, `teal-rust`, `forest-rose`, `cobalt-vermilion`, `plum-ochre`, `sage-lilac`, `olive-coral` and `espresso-ice`. Use one as a theme ID to select its palette automatically, or pass it as `palette` with another compatible theme. The theme still needs explicit, visually curated photo memberships in your collection; no personal images ship with these presets.

Palette metadata exposes optional `majorColours`, containing two swatches from `colours`. Cork classifies photos from their prevalent chromatic swatches, excludes unrelated families and balances the two families' visible area as it fills rectangular gaps. Existing prints count toward that balance. Both families must be available from the mood or retained images when colour matching is enabled. If one is absent, Cork returns a useful error without changing the wall. Fill Empty preserves the placed items and balances only what can fit. Wallpaper must match an actual represented family rather than an average of the two hues; native pixel and crop limits still apply. Single-family palettes retain their original matching behavior.

## Measured colour classifications and custom pairs

`cork_get_collection` reports `colour_families` with IDs, swatches and strong/accent counts, plus `colour_classification` progress/error state. `include_metadata: true` returns each photo's optional `colourProfile`: version 1, `sampleCount`, and `colours` entries containing `family`, `coverage` and `strength` (`strong` or `weak`). Coverage is the fraction of an opaque, colour-managed 64 × 64 sRGB sample assigned to that family. Strong means at least 18%; custom accent matching uses at least 4%. This is a deterministic colour classifier, not semantic image recognition.

Existing photo and wallpaper catalogues are backfilled by the running app without changing source metadata, curated memberships or assets. Normal imports compute profiles from pixels; external manifest claims do not supply these classifications. Atomic metadata caches and their previous copies persist the result, so later launches reuse it. A failed scan preserves the prior complete cache and the saved scene.

Save an ordered pair with `cork_set_desktop({"colour_pair":["red","violet"],"colour_strength":"strong"})`, then call `cork_roll_wall`. The first slot is dominant and the second secondary. Each accepts `random` or a family ID: `red`, `orange`, `yellow`, `green`, `teal`, `blue`, `violet`, `pink`, `brown`, `cream`, `black`, `grey`, `white`. Two fixed families must differ; `random` can occupy either or both slots. For example, `["random","blue"]` keeps blue secondary, `["blue","random"]` keeps blue dominant, and `["random","random"]` refreshes the whole pair. Strength can also be `strong_and_accents`.

The saved preferences retain `random`; each roll resolves a viable, distinct pair, preferring available native-size wallpapers and avoiding the previous random choices when alternatives exist. The concrete result lives in `rotation.scheme.colourFamilies`. Fill Empty and display refits keep that resolved pair while the choices still allow it. Favourites retain both preferences and the exact resolved scene. The pair replaces the preset and searches all classified photos; `palette: "auto"` in `cork_set_desktop` returns to mood-based selection. A per-roll preset palette override retains its existing meaning.

Measured proportions, including retained prints, drive colour balance without weakening source caps or aspect fitting. Custom pairs aim for roughly two-thirds dominant colour area, subject to available images and retained anchors; named paired presets retain their equal balance. Shared paper and neutrals cannot conceal a strongly off-pair subject. Wallpaper ranking requires the dominant family, with a quiet neutral carrying its accent as a fallback. A non-neutral background dominated by the secondary colour cannot substitute for the primary. A missing suitable native-resolution wallpaper retains the current one with the existing visible fallback.

## Reactive layouts and note colours

`hidden` applies to images, notes and widgets. Hidden items are retained through rolls and restarts but release packing space. `match_scene_colours` is a per-note opt-in; the computed pale `matchedNoteColour` is separate from the manual paper choice. Coordinate edits to participating items anchor the edited items and repack the same remaining photo IDs/styles/angles. Overlay-note movement does not trigger packing. Display-size adaptation uses saved `layoutDisplays`, preserves existing content and fills new logical space with a density cap to prevent repeated resize notifications from accumulating tiny prints.

Wallpapers may come from any verified local source, including Unsplash. Keep the original page/photographer provenance where known. Import measures actual dimensions and colours. Optional `automatic: false` retires a background from automatic selection while preserving its media and metadata; omitting the field on a metadata update retains the stored choice. Automatic selection rechecks a candidate against the actual selected photo hues, rejecting a pink/purple background for a clearly blue photo wall.
