import AppKit

// Tiny focus helper for the Cmd+Tab acceptance scripts.
//
// System Events (`tell process ... to set frontmost`) needs the Accessibility
// grant and is unreliable when a CLI-launched app races WindowServer
// registration; it reported "could not focus" and the switch loop then ran
// from whatever app happened to be active. NSRunningApplication is the same
// workspace API the Dock uses and needs no automation permission.
//
//   focus frontmost            prints the frontmost process id
//   focus activate <pid>       activates that process, exit 1 on failure

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: focus frontmost|activate <pid>\n".utf8))
    exit(2)
}

switch arguments[1] {
case "frontmost":
    let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
    print(pid)
case "activate":
    guard arguments.count >= 3, let raw = Int32(arguments[2]),
          let application = NSRunningApplication(processIdentifier: pid_t(raw)) else {
        FileHandle.standardError.write(Data("focus: no process for pid \(arguments.count >= 3 ? arguments[2] : "?")\n".utf8))
        exit(1)
    }
    let activated = application.activate(options: [.activateAllWindows])
    if !activated {
        FileHandle.standardError.write(Data("focus: activate failed for pid \(raw)\n".utf8))
        exit(1)
    }
default:
    FileHandle.standardError.write(Data("unknown command \(arguments[1])\n".utf8))
    exit(2)
}
