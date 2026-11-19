// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenFuse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenFuse", targets: ["OpenFuseApp"]),
        .executable(name: "openfuse-probe", targets: ["openfuse-probe"]),
        .library(name: "OpenFuseCore", targets: ["OpenFuseCore"]),
    ],
    targets: [
        // Thin C shim so Swift can call libmpv's stable client API.
        .systemLibrary(
            name: "CMpv",
            path: "Sources/CMpv",
            providers: [.brew(["mpv"])]
        ),
        .target(
            name: "OpenFuseCore",
            dependencies: ["CMpv"],
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
