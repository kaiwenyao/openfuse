import CoreGraphics
import Foundation

// Acceptance helper: posts a real right-click at a screen point (top-left origin).
// usage: click_event right X Y
let args = CommandLine.arguments
guard args.count >= 4, args[1] == "right", let x = Double(args[2]), let y = Double(args[3]) else {
    FileHandle.standardError.write(Data("usage: click_event right X Y\n".utf8))
    exit(2)
}
let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)
let down = CGEvent(mouseEventSource: source, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right)
let up = CGEvent(mouseEventSource: source, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)
down?.post(tap: .cghidEventTap)
usleep(60_000)
up?.post(tap: .cghidEventTap)
