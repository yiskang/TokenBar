// swift-tools-version: 6.0
import PackageDescription

// The Rust staticlib must be built first: `cargo build --release` (or `make`).
// `swift build` must run from the repo root so the relative -L path resolves.
let package = Package(
    name: "TokenBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "CTB", path: "Sources/CTB"),
        .target(
            name: "TokenBarCore",
            dependencies: ["CTB"],
            path: "Sources/TokenBarCore"
        ),
        .executableTarget(
            name: "TokenBar",
            dependencies: [
                "TokenBarCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/TokenBar",
            resources: [
                .copy("Resources/agent-icons"),
                .copy("Resources/anim-cat2"),
                .copy("Resources/anim-cat2-light"),
                .copy("Resources/anim-parrot"),
                .copy("Resources/anim-parrot-light"),
            ],
            linkerSettings: rustLinkerSettings
        ),
    ]
)

// The Rust staticlib must already exist (cargo build --release) and the link
// must run from the repo root for the relative -L path to resolve.
var rustLinkerSettings: [LinkerSetting] {
    [
        .unsafeFlags(["-L", "target/release", "-ltb_core_ffi"]),
        // Sparkle.framework rides in Contents/Frameworks inside the .app.
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
        .linkedFramework("Security"),
        .linkedFramework("SystemConfiguration"),
        .linkedFramework("CoreFoundation"),
        .linkedLibrary("c++"),
        .linkedLibrary("resolv"),
    ]
}
