import CoreGraphics
import Foundation

// Acceptance helper: posts a real left-button drag at screen points
// (top-left origin). usage: drag_event X1 Y1 X2 Y2 [steps] [stepMs]
let args = CommandLine.arguments
guard args.count >= 5,
      let x1 = Double(args[1]), let y1 = Double(args[2]),
      let x2 = Double(args[3]), let y2 = Double(args[4])
else {
    FileHandle.standardError.write(Data("usage: drag_event X1 Y1 X2 Y2 [steps] [stepMs]\n".utf8))
    exit(2)
}
let steps = args.count > 5 ? max(1, Int(args[5]) ?? 24) : 24
let stepMs = args.count > 6 ? max(1, Int(args[6]) ?? 16) : 16
let source = CGEventSource(stateID: .hidSystemState)
let start = CGPoint(x: x1, y: y1)
let end = CGPoint(x: x2, y: y2)

func post(_ type: CGEventType, _ point: CGPoint) {
    let event = CGEvent(
        mouseEventSource: source,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: .left
    )
    event?.setIntegerValueField(.mouseEventClickState, value: 1)
    event?.post(tap: .cghidEventTap)
}

post(.mouseMoved, start)
usleep(60_000)
post(.leftMouseDown, start)
usleep(60_000)
for step in 1...steps {
    let fraction = Double(step) / Double(steps)
    let point = CGPoint(
        x: x1 + (x2 - x1) * fraction,
        y: y1 + (y2 - y1) * fraction
    )
    post(.leftMouseDragged, point)
    usleep(useconds_t(stepMs * 1000))
}
post(.leftMouseUp, end)
