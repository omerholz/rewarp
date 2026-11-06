// swift-tools-version: 5.9
import Foundation
import PackageDescription

let root = Context.packageDirectory
let vtLinker: [LinkerSetting] = [
    .unsafeFlags(["\(root)/vendor/ghostty-vt/lib/libghostty-vt.a"]),
    .linkedLibrary("c++"),
]

// Without Xcode, SwiftPM does not look here for the Testing framework.
// scripts/test.sh sets this only when the selected developer directory is CLT.
let cltTesting = ProcessInfo.processInfo.environment["REWARP_CLT_TESTING"] == "1"
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltInterop = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let package = Package(
    name: "Rewarp",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CGhosttyVT",
            publicHeadersPath: "include",
            linkerSettings: vtLinker
        ),
        .target(name: "RewarpCore", dependencies: ["CGhosttyVT"]),
        .executableTarget(name: "Rewarp", dependencies: ["RewarpCore", "CGhosttyVT"]),
        .testTarget(
            name: "RewarpCoreTests",
            dependencies: ["RewarpCore", "CGhosttyVT"],
            swiftSettings: cltTesting ? [.unsafeFlags(["-F", cltFrameworks])] : [],
            linkerSettings: cltTesting ? [.unsafeFlags(["-F", cltFrameworks, "-framework", "Testing", "-Xlinker", "-rpath", "-Xlinker", cltFrameworks, "-Xlinker", "-rpath", "-Xlinker", cltInterop])] : []
        ),
    ]
)
