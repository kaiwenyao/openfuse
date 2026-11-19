// Window lookup + capture helper for reproducible UI evidence.
// swiftc -O Tools/window_capture.swift -o build/window_capture
// build/window_capture list [owner]
// then: screencapture -x -l <windowID> out.png
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}

func owner(_ window: [String: Any]) -> String { window[kCGWindowOwnerName as String] as? String ?? "" }
func title(_ window: [String: Any]) -> String { window[kCGWindowName as String] as? String ?? "" }
func number(_ window: [String: Any]) -> Int { window[kCGWindowNumber as String] as? Int ?? 0 }
func bounds(_ window: [String: Any]) -> CGRect {
    guard let dict = window[kCGWindowBounds as String] as? [String: CGFloat] else { return .zero }
    return CGRect(x: dict["X"] ?? 0, y: dict["Y"] ?? 0, width: dict["Width"] ?? 0, height: dict["Height"] ?? 0)
}

if args.count >= 2, args[1] == "list" {
    let needle = args.count > 2 ? args[2].lowercased() : ""
    for window in windows {
        let name = owner(window)
        guard needle.isEmpty || name.lowercased().contains(needle) else { continue }
        let rect = bounds(window)
        print("\(number(window))\t\(name)\t\(title(window))\t\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width)),\(Int(rect.height))")
    }
    exit(0)
}

FileHandle.standardError.write("usage: window_capture list [owner] | shot <id> <path>\n".data(using: .utf8)!)
exit(2)
