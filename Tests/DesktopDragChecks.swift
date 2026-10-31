import AppKit
import CorkCore

@main @MainActor enum DesktopDragChecks {
    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw CorkError(message) }
    }

    static func main() throws {
        _ = NSApplication.shared
        let panel = PrintPanel(contentRect: CGRect(x: 50, y: 100, width: 336, height: 276),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let note = PrintItem(assetFile: "", title: "Test", style: .sticky, x: 100, y: 200,
                             width: 240, height: 180, kind: .note)
        let view = PrintView(item: note, image: nil)
        panel.contentView = view; panel.editing = true; view.editing = true; view.revision = 7
        var patches: [[String: JSONValue]] = [], revisions: [Int] = [], selections = 0
        view.onSelect = { selections += 1 }
        view.onChange = { patches.append($0); revisions.append($1) }
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 1,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else {
                throw CorkError("Could not create an AppKit test event.")
            }
            return event
        }

        view.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 168, y: 138)))
        try check(selections == 1 && view.isDragging, "First press must select and begin dragging.")
        view.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 228, y: 98)))
        try check(view.item.x == 160 && view.item.y == 240 && patches.isEmpty,
                  "Movement must follow the event position and wait for mouse-up to save.")
        view.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 168, y: 138)))
        try check(patches.count == 1 && patches[0]["x"]?.number == 160 && patches[0]["y"]?.number == 240
                  && revisions == [7] && !view.isDragging, "Mouse-up must save exactly once at the starting revision.")
        print("PASS first-press selection, movement and single commit")

        let origin = view.item
        view.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 168, y: 138)))
        for _ in 0..<2 {
            // The panel moves with the pointer, so the next event uses its new origin.
            view.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 188, y: 128)))
        }
        try check(view.item.x == origin.x + 40 && view.item.y == origin.y + 20,
                  "Successive events must not drift when the panel origin changes.")
        view.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 168, y: 138)))
        print("PASS consecutive movement after the panel moves")

        view.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 168, y: 138)))
        let saves = patches.count
        view.editing = false
        view.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 168, y: 138)))
        try check(!view.isDragging && patches.count == saves, "Finishing editing must cancel an unfinished drag.")
        view.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 168, y: 138)))
        try check(!view.isDragging && selections == 3, "Locked paper must not begin another drag.")
        print("PASS finishing editing cancels interaction and locks the paper")

        view.editing = true
        let beforeResize = view.item
        view.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 283, y: 53)))
        view.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 333, y: 53)))
        try check(view.item.width == 290 && view.item.height == 217.5
                  && view.item.x == beforeResize.x && view.item.y == beforeResize.y,
                  "The resize handle must preserve aspect ratio and origin.")
        view.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 333, y: 53)))
        print("PASS resize handle preserves aspect ratio and position")
        print("4/4 desktop drag checks passed; hidden test windows only.")
    }
}
