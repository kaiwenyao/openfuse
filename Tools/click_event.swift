import CoreGraphics
import Foundation

// Acceptance helper: posts a real right-click at a screen point (top-left origin).
// usage: click_event right X Y | click_event move X Y
let args = CommandLine.arguments
guard args.count >= 4, let x = Double(args[2]), let y = Double(args[3]) else {
    FileHandle.standardError.write(Data("usage: click_event right|move X Y\n".utf8))
    exit(2)
}
if args[1] == "left" {
    let point = CGPoint(x: x, y: y)
    let source = CGEventSource(stateID: .combinedSessionState)
    let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
    let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
    let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
    down?.setIntegerValueField(.mouseEventClickState, value: 1)
    up?.setIntegerValueField(.mouseEventClickState, value: 1)
    move?.post(tap: .cghidEventTap)
    usleep(80_000)
    down?.post(tap: .cghidEventTap)
    usleep(80_000)
    up?.post(tap: .cghidEventTap)
    exit(0)
}
if args[1] == "scroll" {
    let scroll = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState),
                         units: .pixel, wheelCount: 1, wheel1: Int32(y), wheel2: 0, wheel3: 0)
    scroll?.post(tap: .cghidEventTap)
    exit(0)
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
