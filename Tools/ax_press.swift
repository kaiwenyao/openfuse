import AppKit
import ApplicationServices

func find(_ element: AXUIElement, role wanted: String, text: String) -> AXUIElement? {
    let role = attr(element, kAXRoleAttribute) as? String ?? ""
    let line = describe(element)
    if role == wanted, line.contains(text) { return element }
    if let children = attr(element, kAXChildrenAttribute) as? [AXUIElement] {
        for child in children {
            if let found = find(child, role: wanted, text: text) { return found }
        }
    }
    return nil
}

func allFields(_ element: AXUIElement) {
    let role = attr(element, kAXRoleAttribute) as? String ?? ""
    if role == "AXTextField" || role == "AXSecureTextField" {
        print("FIELD | \(describe(element))")
    }
    if let children = attr(element, kAXChildrenAttribute) as? [AXUIElement] {
        for child in children { allFields(child) }
    }
}


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
} else if arguments.count >= 3, arguments[2] == "fields" {
    allFields(app)
} else if arguments.count >= 5, arguments[2] == "setText" {
    if let field = find(app, role: "AXTextField", text: arguments[3]) {
        let result = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, arguments[4] as CFTypeRef)
        print("SET \(result.rawValue) \(describe(field))")
    } else {
        print("SET missing field")
    }
} else if arguments.count >= 5, arguments[2] == "pressAt", let x = Double(arguments[3]), let y = Double(arguments[4]) {
    var element: AXUIElement?
    let hit = AXUIElementCopyElementAtPosition(app, Float(x), Float(y), &element)
    var current = element
    var pressed = false
    while let candidate = current {
        var actions: CFArray?
        AXUIElementCopyActionNames(candidate, &actions)
        if let names = actions as? [String], names.contains(kAXPressAction) {
            let result = AXUIElementPerformAction(candidate, kAXPressAction as CFString)
            print("PRESSAT \(hit.rawValue) \(result.rawValue) \(describe(candidate))")
            pressed = true
            break
        }
        var parent: CFTypeRef?
        guard AXUIElementCopyAttributeValue(candidate, kAXParentAttribute as CFString, &parent) == .success,
              let next = parent else { break }
        current = unsafeBitCast(next, to: AXUIElement.self)
    }
    print("pressed: \(pressed)")
} else if arguments.count >= 4, arguments[2] == "press" {
    var pressed = false
    press(app, target: arguments[3], pressed: &pressed)
    print("pressed: \(pressed)")
} else {
    FileHandle.standardError.write(Data("usage: ax_press <pid> press <label> | hit x y\n".utf8))
    exit(2)
}
