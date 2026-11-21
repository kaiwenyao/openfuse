import Foundation

/// `OPENFUSE_DEBUG_TIMING=1` timestamps the open→first-frame pipeline and logs
/// main-thread stalls. Used by `Scripts/run-player-responsiveness.sh` to prove
/// the player no longer blocks the UI while a source is opening.
enum PlaybackTrace {
    static let enabled = ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_TIMING"] == "1"
    private static let start = DispatchTime.now().uptimeNanoseconds
    private static var heartbeatInstalled = false

    static func mark(_ name: String) {
        guard enabled else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let ms = Double(now &- start) / 1_000_000
        let line = String(format: "[timing] %9.1fms %@\n", ms, name)
        FileHandle.standardError.write(Data(line.utf8))
    }

    /// Logs when the main queue is late by more than 250 ms. A blocked main
    /// thread is exactly what made ⌘Tab unable to bring OpenFuse back.
    static func installHeartbeat() {
        guard enabled, !heartbeatInstalled else { return }
        heartbeatInstalled = true
        var last = DispatchTime.now().uptimeNanoseconds
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            let now = DispatchTime.now().uptimeNanoseconds
            let lateMs = Double(now &- last) / 1_000_000 - 50
            if lateMs > 250 {
                mark(String(format: "MAIN-STALL %.0fms", lateMs))
            }
            last = now
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
