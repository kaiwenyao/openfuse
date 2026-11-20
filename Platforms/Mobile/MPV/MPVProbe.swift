import Foundation
import Libmpv

/// Readiness probe for the bundled libmpv: creates a handle, reads the client
/// API version and disposes it. Enabled with `OPENFUSE_MPV_PROBE=1`.
enum MPVProbe {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["OPENFUSE_MPV_PROBE"] == "1" else { return }
        guard let handle = mpv_create() else {
            log("mpv_create failed")
            return
        }
        log("mpv handle ok, client api \(mpv_client_api_version())")
        mpv_terminate_destroy(handle)
    }

    private static func log(_ message: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mpv-probe.log")
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
