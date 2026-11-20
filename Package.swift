// swift-tools-version: 6.0
import PackageDescription

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
    targets: [
        // Thin C shim so Swift can call libmpv's stable client API.
        .systemLibrary(
            name: "CMpv",
            path: "Sources/CMpv",
            providers: [.brew(["mpv"])]
        ),
        .target(
            name: "OpenFuseData",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Security"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .target(
            name: "OpenFuseCore",
            dependencies: ["OpenFuseData", "CMpv"],
            swiftSettings: [
                .unsafeFlags(["-I/opt/homebrew/include"]),
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib"]),
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
                .unsafeFlags(["-L/opt/homebrew/lib"]),
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
                .unsafeFlags(["-L/opt/homebrew/lib"]),
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
                .unsafeFlags(["-L/opt/homebrew/lib"]),
                .linkedLibrary("mpv"),
                .linkedFramework("OpenGL"),
            ]
        ),
    ]
)
