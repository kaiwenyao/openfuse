// swift-tools-version: 6.0
import Foundation
import PackageDescription

/// SMB support links libsmb2 from /opt/homebrew (see Scripts/install-libsmb2.sh).
/// The WebDAV/Jellyfin-only build must not require those headers, so this target
/// is only compiled when libsmb2 is present or OPENFUSE_SMB2=1 is set.
let smb2Enabled: Bool = {
    let environment = ProcessInfo.processInfo.environment
    if let raw = environment["OPENFUSE_SMB2"]?.lowercased() {
        return raw != "0" && raw != "false" && raw != "no"
    }
    return FileManager.default.fileExists(atPath: "/opt/homebrew/include/smb2/libsmb2.h")
}()

var targets: [Target] = []

if smb2Enabled {
    targets.append(.systemLibrary(
        name: "CSMB2",
        path: "Sources/CSMB2",
        pkgConfig: "libsmb2",
        providers: []
    ))
}

targets.append(.target(
    name: "OpenFuseData",
    dependencies: smb2Enabled ? [.target(name: "CSMB2", condition: .when(platforms: [.macOS]))] : [],
    swiftSettings: [
        .swiftLanguageMode(.v5),
        .unsafeFlags(["-Xcc", "-I/opt/homebrew/include"]),
    ] + (smb2Enabled ? [.define("OPENFUSE_SMB2")] : []),
    linkerSettings: [
        .linkedLibrary("sqlite3"),
        .unsafeFlags(["-L/opt/homebrew/lib", "-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib"]),
        .linkedFramework("Security"),
        .linkedFramework("AVFoundation"),
        .linkedFramework("CloudKit"),
    ]
))

let package = Package(
    name: "OpenFuse",
    platforms: [
        .macOS(.v14),
        .iOS(.v18),
        .tvOS(.v18),
        .visionOS(.v2),
    ],
    products: [
        .executable(name: "OpenFuse", targets: ["OpenFuseApp"]),
        .executable(name: "openfuse-probe", targets: ["openfuse-probe"]),
        .library(name: "OpenFuseCore", targets: ["OpenFuseCore"]),
        .library(name: "OpenFuseData", targets: ["OpenFuseData"]),
    ],
    targets: targets + [
        // Thin C shim so Swift can call libmpv's stable client API.
        .systemLibrary(
            name: "CMpv",
            path: "Sources/CMpv",
            providers: [.brew(["mpv"])]
        ),
        .target(
            name: "OpenFuseCore",
            dependencies: ["OpenFuseData", "CMpv"],
            swiftSettings: [
                .unsafeFlags(["-I/opt/homebrew/include"]),
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib", "-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib"]),
                .linkedLibrary("mpv"),
                .linkedLibrary("sqlite3"),
                .linkedFramework("OpenGL"),
            ]
        ),
        .executableTarget(
            name: "OpenFuseApp",
            dependencies: ["OpenFuseCore"],
            swiftSettings: [
                .unsafeFlags(["-I/opt/homebrew/include"]),
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib", "-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib"]),
                .linkedLibrary("mpv"),
                .linkedFramework("OpenGL"),
            ]
        ),
        .executableTarget(
            name: "openfuse-probe",
            dependencies: ["OpenFuseCore"],
            swiftSettings: [
                .unsafeFlags(["-I/opt/homebrew/include"]),
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib", "-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib"]),
                .linkedLibrary("mpv"),
                .linkedFramework("OpenGL"),
            ]
        ),
        .testTarget(
            name: "OpenFuseCoreTests",
            dependencies: ["OpenFuseCore"],
            swiftSettings: [
                .unsafeFlags(["-I/opt/homebrew/include"]),
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib", "-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib"]),
                .linkedLibrary("mpv"),
                .linkedFramework("OpenGL"),
            ]
        ),
    ]
)
