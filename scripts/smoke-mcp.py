#!/usr/bin/env python3
"""Exercise a running isolated Cork through its actual stdio MCP bridge."""
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
if not os.environ.get("CORK_DATA_DIR") or not os.environ.get("CORK_SOCKET"):
    sys.exit("Use absolute CORK_DATA_DIR and CORK_SOCKET for an isolated, running Cork.")

process = subprocess.Popen([str(root / "build/Cork.app/Contents/MacOS/cork-mcp")], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
counter = 0

def rpc(method, params=None, notification=False):
    global counter
    counter += 1
    message = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        message["params"] = params
    if not notification:
        message["id"] = counter
    process.stdin.write(json.dumps(message) + "\n")
    process.stdin.flush()
    if notification:
        return None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    if not selector.select(35):
        raise RuntimeError("MCP response timed out")
    selector.close()
    response = json.loads(process.stdout.readline())
    assert response["id"] == counter and "error" not in response, response
    return response["result"]

def tool(name, arguments=None, error=False):
    result = rpc("tools/call", {"name": name, "arguments": arguments or {}})
    assert result.get("isError", False) == error, result
    if error:
        return result
    return json.loads(result["content"][0]["text"])

try:
    assert rpc("initialize", {"protocolVersion": "2025-11-25", "clientInfo": {"name": "Cork smoke", "version": "1"}, "capabilities": {}})["serverInfo"]["name"] == "Cork"
    rpc("notifications/initialized", notification=True)
    assert len(rpc("tools/list")["tools"]) == 28
    initial = tool("cork_get_board")
    assert initial["ready"] and not initial["items"], "Use an empty isolated board"
    for index, style in enumerate(["tape", "pushpin", "polaroid", "frame"]):
        board = tool("cork_add_image", {"path": str(root / f"docs/assets/sample-{index + 1}.png"), "style": style, "title": ["Quiet hours", "Take the long way", "A small collection", "Room to grow"][index]})
    board = tool("cork_add_note", {"text": "A little space for what matters.", "title": "Keep in sight", "style": "flat", "note_color": "cream"})
    board = tool("cork_add_note", {"text": "Print something.\nMake time.\nTake the scenic route.", "title": "For later", "style": "sticky"})
    assert len(board["items"]) == 6
    revision = board["revision"]
    ids = [item["id"] for item in board["items"]]
    tool("cork_update_items", {"items": [{"id": ids[0], "width": -10}]}, error=True)
    tool("cork_add_note", {"text": 42}, error=True)
    assert tool("cork_get_board")["revision"] == revision
    updates = [{"id": item_id, "x": 70 + index * 100, "y": 100 + index * 40, "rotation": index - 3} for index, item_id in enumerate(ids)]
    before_arrange = tool("cork_update_items", {"items": updates, "expected_revision": revision})
    tool("cork_arrange", {"layout": "gallery", "expected_revision": revision}, error=True)
    arranged = tool("cork_arrange", {"layout": "collage", "expected_revision": before_arrange["revision"]})
    assert arranged["items"][0]["x"] != before_arrange["items"][0]["x"]
    undone = tool("cork_undo")
    assert undone["items"] == before_arrange["items"] and undone["revision"] > arranged["revision"]
    board = tool("cork_arrange", {"layout": "collage"})
    assert tool("cork_set_edit_mode", {"enabled": True})["editing"]
    assert not tool("cork_set_edit_mode", {"enabled": False})["editing"]
    screenshot = rpc("tools/call", {"name": "cork_screenshot_desktop", "arguments": {"mode": "desktop", "max_width": 1600}})
    if screenshot.get("isError"):
        message = screenshot["content"][0]["text"]
        assert "Screen Recording" in message, message
        capture_status = "permission denial returned with recovery instructions"
    else:
        assert screenshot["content"][1]["type"] == "image"
        metadata = json.loads(screenshot["content"][0]["text"])
        assert Path(metadata["path"]).is_file() and metadata["pixel_width"] == 1600
        capture_status = "desktop image and scale returned"
    result = tool("cork_get_board")
    (root / "build/verification-board.json").write_text(json.dumps(result, indent=2))
    print("PASS initialize, tool discovery, 4 image styles, 2 note styles, atomic edits, invalid arguments, stale revisions, layout, undo, edit lock")
    print("PASS screenshot: " + capture_status)
    print("Saved 6-item board at revision " + str(result["revision"]))
finally:
    process.stdin.close()
    process.wait(timeout=5)
