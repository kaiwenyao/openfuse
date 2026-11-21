import AppKit
import ApplicationServices

// Acceptance helper: drives SwiftUI buttons through the accessibility API.
// usage: ax_press <pid> press <label-substring>
//        ax_press <pid> hit <screen-x> <screen-y>
func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func describe(_ element: AXUIElement) -> String {
    let role = attr(element, kAXRoleAttribute) as? String ?? ""
    let title = attr(element, kAXTitleAttribute) as? String ?? ""
    let description = attr(element, kAXDescriptionAttribute) as? String ?? ""
    let value = attr(element, kAXValueAttribute) as? String ?? ""
    return "\(role) | \(title) | \(description) | \(value.prefix(120))"
}

func press(_ element: AXUIElement, target: String, pressed: inout Bool) {
    let line = describe(element)
    let role = attr(element, kAXRoleAttribute) as? String ?? ""
    let pressableRoles: Set<String> = ["AXButton", "AXRadioButton", "AXMenuItem", "AXCell", "AXCheckBox"]
    if !pressed, pressableRoles.contains(role), line.contains(target) {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        print("PRESS \(result.rawValue) \(line)")
        pressed = true
    }
    if let children = attr(element, kAXChildrenAttribute) as? [AXUIElement] {
        for child in children { press(child, target: target, pressed: &pressed) }
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 2, let pid = pid_t(arguments[1]) else { exit(2) }
let app = AXUIElementCreateApplication(pid)
if arguments.count >= 5, arguments[2] == "hit", let x = Double(arguments[3]), let y = Double(arguments[4]) {
    var element: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(app, Float(x), Float(y), &element)
    print("HIT \(result.rawValue) \(element.map(describe) ?? "nil")")
} else if arguments.count >= 4, arguments[2] == "press" {
    var pressed = false
    press(app, target: arguments[3], pressed: &pressed)
    print("pressed: \(pressed)")
} else {
    FileHandle.standardError.write(Data("usage: ax_press <pid> press <label> | hit x y\n".utf8))
    exit(2)
}
