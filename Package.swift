// swift-tools-version: 5.9
import Foundation
import PackageDescription

let root = Context.packageDirectory
let vtLinker: [LinkerSetting] = [
    .unsafeFlags(["\(root)/vendor/ghostty-vt/lib/libghostty-vt.a"]),
    .linkedLibrary("c++"),
]

// Without Xcode, SwiftPM does not look here for the Testing framework.
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
            swiftSettings: [.unsafeFlags(["-F", cltFrameworks])],
            linkerSettings: [.unsafeFlags(["-F", cltFrameworks, "-framework", "Testing", "-Xlinker", "-rpath", "-Xlinker", cltFrameworks, "-Xlinker", "-rpath", "-Xlinker", cltInterop])]
        ),
    ]
)
