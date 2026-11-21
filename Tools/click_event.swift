import CoreGraphics
import Foundation

// Acceptance helper: posts a real right-click at a screen point (top-left origin).
// usage: click_event right X Y | click_event move X Y
let args = CommandLine.arguments
guard args.count >= 4, let x = Double(args[2]), let y = Double(args[3]) else {
    FileHandle.standardError.write(Data("usage: click_event right|move X Y\n".utf8))
    exit(2)
}
if args[1] == "move" {
    let move = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState),
                       mouseType: .mouseMoved,
                       mouseCursorPosition: CGPoint(x: x, y: y),
                       mouseButton: .left)
    move?.post(tap: .cghidEventTap)
    exit(0)
}
guard args[1] == "right" else {
    FileHandle.standardError.write(Data("usage: click_event right|move X Y\n".utf8))
    exit(2)
}
let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)
let down = CGEvent(mouseEventSource: source, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right)
let up = CGEvent(mouseEventSource: source, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)
down?.post(tap: .cghidEventTap)
usleep(60_000)
up?.post(tap: .cghidEventTap)
