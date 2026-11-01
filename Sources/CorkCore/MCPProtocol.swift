import Foundation

public enum CorkTools {
    static func property(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }
    static func schema(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        .object(["type": .string("object"), "properties": .object(properties),
                 "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false)])
    }
    static func choice(_ values: [String], _ description: String) -> JSONValue {
        .object(["type": .string("string"), "enum": .array(values.map(JSONValue.string)), "description": .string(description)])
    }
    static let ids: JSONValue = .object(["type": .string("array"), "minItems": .number(1), "maxItems": .number(500),
                                        "items": .object(["type": .string("string")])])
    public static var definitions: [JSONValue] {
        let number = { (name: String) in property("number", name) }
        let display = property("integer", "Display ID from cork_get_board. Defaults to the primary display.")
        let style = choice(PrintStyle.allCases.map(\.rawValue), "Physical print treatment.")
        let patch = schema([
            "id": property("string", "Stable item UUID."), "x": number("Left edge in screen-local points."),
            "y": number("Top edge in screen-local points."), "width": number("Decorated print width; scales height unless provided."),
            "height": number("Decorated print height."), "rotation": number("Clockwise degrees, −180…180."),
            "style": style, "title": property("string", "Title; also the Polaroid caption."),
            "keep_in_place": property("boolean", "Keep this image through randomization and automatic layouts; manual edits remain available."),
            "include_in_layout": property("boolean", "Notes only. True reserves layout space; false leaves the note in place above pictures and lets layouts fill behind it."),
            "hidden": property("boolean", "Hide without removing the item; hidden items reserve no layout space and are retained through rolls."),
            "match_scene_colours": property("boolean", "Notes only. Automatically match paper tint to the collage while retaining its manual paper colour."),
            "widget_state": .object(["type": .string("object"), "description": .string("Widget-local state, at most 64 KB. Does not execute code.")]),
            "display_id": display, "z_index": property("integer", "Stacking order; larger is in front."),
            "text": property("string", "Text note body, at most 20,000 characters."),
            "note_color": choice(NoteColor.allCases.map(\.rawValue), "Text note paper color.")
        ], required: ["id"])
        let entries: [(String, String, JSONValue, Bool, Bool)] = [
            ("cork_get_board", "Inspect all prints, stable IDs, display sizes/safe areas, revision, edit state and screenshot permission. Coordinates use a display-local upper-left origin in points.", schema([:]), true, false),
            ("cork_get_favourites", "List locally saved favourite corkboards, including their original layouts and wallpaper references.", schema([:]), true, false),
            ("cork_save_favourite", "Save the current corkboard and wallpaper as a named favourite. Reuses existing media; no image copies.", schema([
                "name": property("string", "Favourite name, 1–120 characters."), "expected_revision": property("integer", "Optional current board revision.")
            ], required: ["name"]), false, false),
            ("cork_load_favourite", "Restore a saved favourite and fit it to current displays. Keeps global shortcuts, schedule and desktop visibility preferences. Undoable.", schema([
                "id": property("string", "Favourite UUID from cork_get_favourites."), "expected_revision": property("integer", "Optional current board revision.")
            ], required: ["id"]), false, false),
            ("cork_remove_favourite", "Remove a favourite bookmark. Keeps the current wall and all image media.", schema(["id": property("string", "Favourite UUID.")], required: ["id"]), false, true),
            ("cork_set_schedule", "Save an explicitly requested periodic randomization schedule. Off by default. Uses current mood/colours; sleep catches up once. Times use the local calendar; nextRun is computed by Cork.", schema([
                "schedule": schema(["frequency": choice(RandomizationFrequency.allCases.map(\.rawValue), "off, minute, hour, day, week, morning_evening, custom"),
                    "every": property("integer", "Custom interval count, 1 through one year's worth."), "unit": choice(ScheduleUnit.allCases.map(\.rawValue), "Custom interval unit."),
                    "hour": property("integer", "Local hour, 0–23."), "minute": property("integer", "Minute, 0–59."), "weekday": property("integer", "Weekly day: Sunday=1, Monday=2, … Saturday=7."),
                    "eveningHour": property("integer", "Second local hour for morning/evening."), "eveningMinute": property("integer", "Second minute.")
                ], required: ["frequency", "every", "unit", "hour", "minute", "weekday", "eveningHour", "eveningMinute"]),
                "expected_revision": property("integer", "Optional current board revision.")
            ], required: ["schedule"]), false, false),
            ("cork_get_widgets", "List registered local widget providers and their widgets.", schema([:]), true, false),
            ("cork_register_widgets", "Register a selected app's local widget manifest and copy its resources. Widget code runs locally with network and outside-file access blocked.", schema(["path": property("string", "Absolute path to the app's widget manifest JSON.")], required: ["path"]), false, false),
            ("cork_add_widget", "Place an interactive registered widget on the desktop and reflow the same photos around it. Undoable; per-instance state saves locally.", schema([
                "provider": property("string", "Registered provider ID."), "widget": property("string", "Widget ID from the provider manifest."),
                "widget_state": .object(["type": .string("object"), "description": .string("Optional initial per-instance state, at most 64 KB.")]),
                "x": number("Left in display-local points."), "y": number("Top in display-local points."), "width": number("Width in points."), "height": number("Height in points."),
                "display_id": display, "expected_revision": property("integer", "Optional board revision.")
            ], required: ["provider", "widget"]), false, false),
            ("cork_minimize_all_windows", "Minimize currently open windows across Mac apps, only when the user requests it. Requires Cork's Accessibility permission. Sets actual window minimization; never hides apps, toggles Show Desktop or restores windows. Returns counts and partial-failure information. Cork desktop paper and wallpaper remain visible.", schema([:]), false, false),
            ("cork_set_desktop_controls", "Save the user's minimize-all, quick-randomize shortcuts and anchored third-finger swipe preference. Only configure these when requested. Does not grant Accessibility permission or minimize windows. Shortcut conflicts preserve the previous saved configuration.", schema([
                "shortcut_enabled": property("boolean", "Enable the global keyboard shortcut."),
                "gesture_enabled": property("boolean", "Enable two steady fingers plus a downward swipe with the third."),
                "key_code": property("integer", "Mac virtual key code, 0…127. Provide modifiers and key_label with it."),
                "modifiers": property("integer", "Bits: Command=1, Option=2, Control=4, Shift=8. Include Command, Option or Control."),
                "key_label": property("string", "Display name for the physical key, e.g. M or F6."),
                "randomize_enabled": property("boolean", "Enable the global randomize-wall shortcut (default Control-Option-Command-R)."),
                "randomize_key_code": property("integer", "Mac virtual key code for randomize, 0…127; provide all three randomize key fields."),
                "randomize_modifiers": property("integer", "Randomize modifiers: Command=1, Option=2, Control=4, Shift=8."),
                "randomize_key_label": property("string", "Display name of the randomize key."),
                "expected_revision": property("integer", "Optional current board revision.")
            ]), false, false),
            ("cork_get_collection", "Inspect the local rotation collection, curated moods, colour families with strong/accent counts, classification progress and metadata path. include_metadata returns every photo's source, tags, palette, measured colourProfile and mood assignments.", schema([
                "include_metadata": property("boolean", "Return per-photo metadata; defaults to false. Pages contain at most 500 photos."),
                "offset": property("integer", "Zero-based page offset; default 0."),
                "limit": property("integer", "Page size 1–500; default 500."),
                "ids": .object(["type": .string("array"), "items": .object(["type": .string("string")]), "maxItems": .number(200)]),
                "source_urls": .object(["type": .string("array"), "items": .object(["type": .string("string")]), "maxItems": .number(200)])
            ]), true, false),
            ("cork_import_collection", "Import a selected local JSON collection manifest and copy its images/videos. Merges by stable media ID without changing the wall. Manifest schemaVersion 1: themes [{id,name,description}], photos [{id,path,title,description,sourceURL,sourceBoard,tags,palette,themeIDs,kind?}]. kind may be image or video; omitted means image. Use verified local download paths and original source URLs. Videos create a still cover and measured frame profiles. Optional removeIDs excludes selected catalogue IDs from future rolls without deleting media or changing saved scenes. Import or exclude at most 200 IDs per manifest; use batches of about 20 new prints; inspect the collection after an ambiguous response before resuming.", schema([
                "path": property("string", "Absolute local manifest JSON path, up to 5 MB and 1–200 import/exclusion IDs per manifest.")
            ], required: ["path"]), false, false),
            ("cork_roll_wall", "Greedily fill a wall from the saved local image/video collection. Uses one curated visual mood, balances both colour families for paired palettes, mixes at least three source boards when available with about a 40% per-board cap, and selects photo aspect ratios for rectangular gaps. Favors fresh photos, mixes print types, and leaves captions blank. Replaces image/video prints on one display; preserves notes, widgets and other displays. Atomic, saved, and undoable; no network request.", schema([
                "theme": property("string", "Mood ID from cork_get_collection, or auto. Defaults to the saved mood choice."),
                "palette": property("string", "Optional palette ID from cork_get_wallpapers."),
                "colour_aware": property("boolean", "Override the saved colour matching preference for this roll."),
                "seed": property("integer", "Optional reproducible seed, 0…2147483647."), "display_id": display,
                "expected_revision": property("integer", "Optional current board revision.")
            ]), false, false),
            ("cork_fill_empty", "Keep every existing print and note exactly where it is and add palette-matching image/video prints in the free rectangles. Does not move or remove existing items. Saved, atomic and undoable; honours the widget checkbox. Uses the current mood where possible, derives the palette from existing images, and can choose a matching native-resolution wallpaper when enabled.", schema([
                "theme": property("string", "Optional mood ID."), "palette": property("string", "Optional palette ID from cork_get_wallpapers."),
                "colour_aware": property("boolean", "Override the saved image-colour matching preference for this fill."),
                "seed": property("integer", "Reproducible seed, 0…2147483647."), "display_id": display,
                "expected_revision": property("integer", "Optional board revision.")
            ]), false, false),
            ("cork_get_wallpapers", "Inspect managed wallpapers, actual pixel dimensions, source Pinterest links, extracted colours, available scene palettes and native-resolution display eligibility.", schema([:]), true, false),
            ("cork_import_wallpapers", "Import selected local high-resolution wallpaper images with provenance. JSON schemaVersion 1: wallpapers [{id,path,title,sourceURL,sourceBoard,themeIDs}]. Colours and actual dimensions are measured locally. Copies are owned by Cork, merged by ID, and do not change the current wall.", schema([
                "path": property("string", "Absolute manifest JSON path, up to 2 MB and 1–50 wallpapers.")
            ], required: ["path"]), false, false),
            ("cork_add_image", "Copy an explicitly selected local image into Cork and put it on the desktop. Use the Pinterest plugin to download a pin first; pass its verified path and source URL. No arbitrary URL fetch or Pinterest credentials.", schema([
                "path": property("string", "Absolute local image path, ≤50 MB."), "title": property("string", "Optional title/caption."),
                "source_url": property("string", "Optional Pinterest pin/original source URL for attribution."), "style": choice(PrintStyle.imageStyles.map(\.rawValue), "Image treatment."),
                "x": number("Left in display-local points."), "y": number("Top in display-local points."),
                "width": number("Decorated print width, 64…4000 points."), "rotation": number("Clockwise degrees."), "display_id": display
            ], required: ["path"]), false, false),
            ("cork_add_video", "Copy a selected local MP4, MOV or M4V into Cork as a physical print. Static cover at rest; hover plays silently, leaving restores the cover. Measures cover colours and five spread-out frames for palette matching. Same treatments, geometry, layout, visibility, favourites and persistence as image prints. No URL download or account credentials.", schema([
                "path": property("string", "Absolute local video path, under 200 MB and at most ten minutes."),
                "title": property("string", "Optional title/caption; blank by default."), "source_url": property("string", "Original source URL for attribution."),
                "style": choice(PrintStyle.imageStyles.map(\.rawValue), "Print treatment."),
                "x": number("Left in display-local points."), "y": number("Top in display-local points."),
                "width": number("Decorated width, 64…4000 points."), "rotation": number("Clockwise degrees."), "display_id": display
            ], required: ["path"]), false, false),
            ("cork_add_note", "Add a text note to the desktop, with flat paper or a shaded sticky note. Text remains editable and local. Arrange notes with the same tools as images.", schema([
                "text": property("string", "Note body, at most 20,000 characters."), "title": property("string", "Optional note title."),
                "style": choice(["flat", "sticky"], "Defaults to sticky."), "note_color": choice(NoteColor.allCases.map(\.rawValue), "Defaults to yellow."),
                "include_in_layout": property("boolean", "Defaults to true. False floats this note above pictures without reserving layout space."),
                "match_scene_colours": property("boolean", "Automatically coordinate this note's paper colour with the collage."),
                "x": number("Left in display-local points."), "y": number("Top in display-local points."),
                "width": number("Note width in points."), "height": number("Note height in points."),
                "rotation": number("Clockwise degrees."), "display_id": display
            ], required: ["text"]), false, false),
            ("cork_update_items", "Move, resize, rotate, style or caption multiple prints atomically as one undoable change. Coordinate edits anchor the changed items and reflow the same photos around them; overlay-note movement stays independent. Inspect board and screenshot first. expected_revision prevents overwriting a newer manual edit.", schema([
                "items": .object(["type": .string("array"), "minItems": .number(1), "maxItems": .number(500), "items": patch]),
                "expected_revision": property("integer", "Optional board revision from cork_get_board.")
            ], required: ["items"]), false, false),
            ("cork_arrange", "Arrange all or selected prints within a display's usable desktop area. Preserves image proportions; undoable. Use screenshot to inspect the result and update_items to refine it.", schema([
                "layout": choice(LayoutKind.allCases.map(\.rawValue), "greedy fills large free rectangles with the existing prints and preserves notes, widgets and other displays; gallery is straight with modest sizes; grid uses cells; collage adds small rotations. Dice rolls also choose photos by aspect ratio."),
                "ids": ids, "display_id": display, "gap": number("Spacing in points, 0…200; defaults to 16 for greedy, otherwise 28."),
                "expected_revision": property("integer", "Optional board revision.")
            ], required: ["layout"]), false, false),
            ("cork_remove_items", "Remove selected prints from the wall. Undoable; original images and Cork's local copies are kept.", schema(["ids": ids, "expected_revision": property("integer", "Optional board revision.")], required: ["ids"]), false, true),
            ("cork_undo", "Undo the latest committed manual or agent change. Use get_board afterward; revisions always increase. expected_revision protects newer user edits.", schema(["expected_revision": property("integer", "Optional current board revision.")]), false, false),
            ("cork_set_edit_mode", "Enable or finish manual desktop editing. Locked prints pass mouse clicks through and sit below apps. MCP arrangement works while locked. Editing brings the prints forward until Done/Escape.", schema(["enabled": property("boolean", "Whether manual desktop editing is enabled.")], required: ["enabled"]), false, false),
            ("cork_set_desktop", "Save desktop visibility and wallpaper settings. hide_files covers desktop file icons only while Cork runs; no files move and icons return on quit. Image/video paths are copied locally; videos loop muted. All choices restore at the next Cork launch. Check desktop_runtime after loading; wallpaper_kind system uses the Mac's original wallpaper.", schema([
                "hide_files": property("boolean", "Hide Desktop file/folder icons while Cork runs."),
                "hide_widgets": property("boolean", "Cover Apple desktop widgets while Cork runs and let new layouts use their area."),
                "match_colours": property("boolean", "Choose images that complement the scene palette."),
                "match_wallpaper": property("boolean", "Choose a native-resolution wallpaper for the palette on future rolls or fills."),
                "palette": property("string", "Palette ID from cork_get_wallpapers, or auto to use the mood/kept images."),
                "colour_pair": .object(["type": .string("array"), "minItems": .number(2), "maxItems": .number(2),
                    "items": choice(ColourChoice.allCases.map(\.rawValue), "Colour family or random."),
                    "description": .string("Ordered dominant and secondary colour choices. Each is a family ID or random, resolved on each roll while fixed slots stay fixed. The first guides the wallpaper and larger colour share. Fill Empty and display refits retain the resolved pair. Searches the whole classified collection and replaces the preset palette. Use palette auto for curated moods.")]),
                "colour_strength": choice(ColourSelectionStrength.allCases.map(\.rawValue), "strong requires 18% image coverage; strong_and_accents includes 4% accents. Saved with the pair."),
                "wallpaper_kind": choice(["system", "image", "video"], "Original system wallpaper, imported image, or looping video."),
                "path": property("string", "Absolute local file, required for image/video wallpaper. Images ≤50 MB; videos ≤2 GB."),
                "paused": property("boolean", "Pause or resume a selected video wallpaper."),
                "default_image_style": choice(PrintStyle.imageStyles.map(\.rawValue), "Saved default treatment for new images."),
                "rotation_theme": property("string", "Save a mood ID from cork_get_collection, or auto for a different surprise mood on each roll."),
                "expected_revision": property("integer", "Optional board revision.")
            ]), false, false),
            ("cork_set_login_item", "Enable or disable Cork as a native macOS login item, only when requested by the user. Requires the installed /Applications/Cork.app. Inspect login_item in the returned board for enabled or requires_approval; macOS may require approval in Login Items settings.", schema([
                "enabled": property("boolean", "Whether Cork should open at login.")
            ], required: ["enabled"]), false, false),
            ("cork_screenshot_desktop", "Capture a display as PNG and return an MCP image plus the file path and coordinate scale. Requires Cork's macOS Screen Recording permission. desktop mode excludes other apps and Cork controls; visible mode includes on-screen apps and may capture private content. Nothing is uploaded by Cork.", schema([
                "display_id": display, "mode": choice(["desktop", "visible"], "Defaults to desktop. visible captures what is on screen, including other apps."),
                "max_width": number("Output pixel width, 320…2560; defaults to 1600.")
            ]), true, false)
        ]
        return entries.map { name, description, input, readOnly, destructive in
            .object(["name": .string(name), "description": .string(description), "inputSchema": input,
                     "annotations": .object(["readOnlyHint": .bool(readOnly), "destructiveHint": .bool(destructive), "openWorldHint": .bool(false)])])
        }
    }
    public static var names: Set<String> { Set(definitions.compactMap { $0["name"]?.string }) }

    public static func validate(name: String, arguments: [String: JSONValue]) throws {
        guard let definition = definitions.first(where: { $0["name"]?.string == name }), let input = definition["inputSchema"] else { throw CorkError("Unknown Cork tool.") }
        try validateValue(.object(arguments), schema: input, path: "arguments")
    }
    private static func validateValue(_ value: JSONValue, schema: JSONValue, path: String) throws {
        let type = schema["type"]?.string
        let valid: Bool
        switch type {
        case "object": valid = value.object != nil
        case "array": valid = value.array != nil
        case "string": valid = value.string != nil
        case "number": valid = value.number?.isFinite == true
        case "integer": valid = value.number.map { $0.isFinite && $0.rounded() == $0 } ?? false
        case "boolean": valid = value.bool != nil
        default: valid = true
        }
        guard valid else { throw CorkError("\(path) must be a \(type ?? "valid value").") }
        if let choices = schema["enum"]?.array, !choices.contains(value) { throw CorkError("\(path) has an unsupported value.") }
        if let object = value.object, let properties = schema["properties"]?.object {
            for key in schema["required"]?.array?.compactMap(\.string) ?? [] where object[key] == nil { throw CorkError("\(path).\(key) is required.") }
            if schema["additionalProperties"]?.bool == false, !Set(object.keys).isSubset(of: Set(properties.keys)) { throw CorkError("\(path) contains an unknown property.") }
            for (key, child) in object { if let childSchema = properties[key] { try validateValue(child, schema: childSchema, path: "\(path).\(key)") } }
        }
        if let array = value.array {
            if let count = schema["minItems"]?.number, Double(array.count) < count { throw CorkError("\(path) is empty.") }
            if let count = schema["maxItems"]?.number, Double(array.count) > count { throw CorkError("\(path) has too many items.") }
            if let itemSchema = schema["items"] { for child in array { try validateValue(child, schema: itemSchema, path: path + "[]") } }
        }
    }
}

/// Pure protocol dispatch; the bridge supplies the actual app transport.
public struct MCPDispatcher: Sendable {
    private var initialized = false
    public init() {}
    public mutating func respond(_ message: JSONValue,
                                call: (String, [String: JSONValue]) throws -> JSONValue) -> JSONValue? {
        let id = message["id"] ?? .null
        func response(_ value: JSONValue) -> JSONValue { .object(["jsonrpc": .string("2.0"), "id": id, "result": value]) }
        func error(_ code: Double, _ text: String) -> JSONValue {
            .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .number(code), "message": .string(text)])])
        }
        guard message.object != nil, message["jsonrpc"]?.string == "2.0", let method = message["method"]?.string else { return error(-32600, "Invalid JSON-RPC request.") }
        if message["id"] == nil { return nil } // notifications never receive a response
        guard id.string != nil || id.number != nil else { return error(-32600, "Request id must be a string or number.") }
        if method == "initialize" {
            guard let requested = message["params"]?["protocolVersion"]?.string else { return error(-32602, "Missing protocolVersion.") }
            let versions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
            initialized = true
            return response(.object([
                "protocolVersion": .string(versions.contains(requested) ? requested : versions[0]),
                "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
                "serverInfo": .object(["name": .string("Cork"), "version": .string("0.10.1")]),
                "instructions": .string("Use cork_get_board, then add local images (Pinterest downloads come from the Pinterest plugin). Arrange with revision checks, inspect cork_screenshot_desktop, refine geometry, and undo mistakes. Coordinates: upper-left of each full display, points; image responses report pixel-to-point scale. Cork app owns all state.")
            ]))
        }
        if method == "ping" { return response(.object([:])) }
        guard initialized else { return error(-32002, "Initialize the MCP session first.") }
        switch method {
        case "tools/list": return response(.object(["tools": .array(CorkTools.definitions)]))
        case "tools/call":
            guard let params = message["params"]?.object, let name = params["name"]?.string,
                  CorkTools.names.contains(name), let arguments = (params["arguments"] ?? .object([:])).object else { return error(-32602, "Unknown tool or invalid arguments.") }
            do { return response(try call(name, arguments)) }
            catch { return response(.toolError(error.localizedDescription)) }
        default: return error(-32601, "Method not found.")
        }
    }
}
