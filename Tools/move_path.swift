import CoreGraphics
import Foundation

// Posts a path of real mouse-moved events. SwiftUI's onHover only sees
// enter/exit transitions when the cursor actually crosses the view boundary,
// so a single jump can miss it in acceptance runs.
// usage: move_path X1 Y1 X2 Y2 [steps] [stepMs]
let args = CommandLine.arguments
guard args.count >= 5,
      let x1 = Double(args[1]), let y1 = Double(args[2]),
      let x2 = Double(args[3]), let y2 = Double(args[4])
else {
    FileHandle.standardError.write(Data("usage: move_path X1 Y1 X2 Y2 [steps] [stepMs]\n".utf8))
    exit(2)
}
let steps = args.count > 5 ? max(1, Int(args[5]) ?? 30) : 30
let stepMs = args.count > 6 ? max(1, Int(args[6]) ?? 20) : 20
let source = CGEventSource(stateID: .hidSystemState)
for step in 0...steps {
    let fraction = Double(step) / Double(steps)
    let point = CGPoint(x: x1 + (x2 - x1) * fraction, y: y1 + (y2 - y1) * fraction)
    let move = CGEvent(
        mouseEventSource: source,
        mouseType: .mouseMoved,
        mouseCursorPosition: point,
        mouseButton: .left
    )
    move?.post(tap: .cghidEventTap)
    usleep(useconds_t(stepMs * 1000))
}
