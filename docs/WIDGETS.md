# Local widgets

Cork 0.6 supports local widget packages supplied by other apps. Swingset is the first provider, with ten fidgets. Register an app's manifest in **Settings → Widgets → Register Widget Provider…**, then use **Add Widget**. Apps can do both operations through the bundled MCP bridge. This is a local registry, without a hosted marketplace or remote code download.

## Package

Keep a manifest and all resources in one directory. The included [counter package](examples/counter/manifest.json) is a complete runnable example. Register its absolute manifest path to try it.

```json
{
  "schemaVersion": 1,
  "id": "dev.example.counter",
  "name": "Local Counter",
  "version": "1.0.0",
  "widgets": [{
    "id": "counter",
    "name": "Counter",
    "description": "A small local counter.",
    "entry": "index.html",
    "width": 230,
    "height": 160
  }]
}
```

IDs are stable ASCII letters, numbers, dots, underscores or hyphens, up to 120 characters, without a leading dot. A provider has 1–50 definitions with unique IDs. Entry paths are relative HTML files inside the package; `..`, absolute entry paths and symbolic links are rejected. Initial dimensions are 96–1200 logical points. Put shared resources beside the HTML entry, since WebKit read access is limited to that entry's directory.

Registration validates and copies the package to a UUID directory under Cork's private `Widgets/` folder and atomically updates `widgets.json`, preserving a previous registry. A package is limited to 200 files and 20 MB. Supported extensions are HTML, JS, CSS, JSON, PNG, JPG/JPEG, SVG, WebP, WOFF/WOFF2, WAV and MP3. The manifest is limited to 500 KB; the registry supports 100 providers. All declared HTML entries must exist.

Re-register the same provider ID to update its copied package. Existing widget references use the new definitions; keep widget IDs compatible across updates. Old package directories are retained for recovery. Register only a provider the user chose or explicitly asked to integrate.

## Host contract

The widget ID is in `location.hash`. Cork loads the entry in a nonpersistent `WKWebView`, with no shared browser cookies or account. It applies an early restrictive Content Security Policy and compiled network rules before loading. HTTP(S), WebSocket and FTP requests are blocked; arbitrary navigation, file pickers, microphone and camera are denied. There is no native command, shell, screenshot, credential or arbitrary-file bridge. Widgets cannot change these host restrictions.

Expose optional lifecycle methods:

```js
window.corkWidget = {
  restore(state = {}) { /* Update local state and draw; do not emit it back. */ },
  pause(paused) { /* Stop animation/work when true; make this idempotent. */ }
};
```

Publish state after a meaningful action or when motion settles:

```js
window.webkit.messageHandlers.cork.postMessage({
  type: 'state',
  state: { count: 3 }
});
```

State must be a JSON object under 64 KB. Cork debounces saves for 150 ms, serializes them with other board work, and retains each instance's state in `board.json`. Toy-local saves do not increment the layout revision or add Undo steps; layout Undo retains current state for surviving widget IDs. An agent's explicit `widget_state` patch is an ordinary undoable edit. Avoid per-frame messages; Swingset sends a bounded checkpoint once per second during sustained motion.

Optional output feedback is rate limited by the host:

```js
window.webkit.messageHandlers.cork.postMessage({ type: 'feedback', kind: 'detent' });
```

Respect the user's haptics preference before sending feedback. Audio must remain optional and start from an intentional interaction. Use native semantic HTML controls, names and keyboard input. Honor `prefers-reduced-motion`, stop work when settled, handle pointer cancellation and visibility changes, and make repeated restore/pause calls harmless. Cork pauses desktop surfaces during display sleep and inactive sessions. Hiding a widget closes its surface; showing it restores the saved state.

## Register and add through MCP

Send these as `tools/call` arguments after MCP initialization:

```json
{"name":"cork_register_widgets","arguments":{"path":"/absolute/path/to/manifest.json"}}
```

```json
{"name":"cork_add_widget","arguments":{"provider":"dev.example.counter","widget":"counter","widget_state":{"count":3},"x":100,"y":300}}
```

`cork_get_widgets` lists registered provider manifests and source paths. `cork_add_widget` also accepts dimensions, display ID and `expected_revision`. Cork reflows the same photos around the new widget in one undoable change. A board supports up to 20 interactive widgets within its 500-item total. Widgets stay fixed during automatic layouts and cannot rotate. Use `cork_update_items` to move, resize, hide or supply `widget_state`; use `cork_remove_items` to remove an instance.

Each instance is independent. Copying a toy to Cork does not create a bidirectional link to its source app. Quitting the source app or moving its original resources does not break the registered copy. Updating the source app requires registering its new package version; Swingset checks its version on the next Add to Cork.
