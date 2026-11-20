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
        .systemLibrary(
            name: "CSMB2",
            path: "Sources/CSMB2",
            pkgConfig: "libsmb2",
            providers: []
        ),
        .target(
            name: "OpenFuseData",
            dependencies: [.target(name: "CSMB2", condition: .when(platforms: [.macOS]))],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-Xcc", "-I/opt/homebrew/include"]),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .unsafeFlags(["-L/opt/homebrew/lib", "-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib"]),
                .linkedFramework("Security"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CloudKit"),
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
