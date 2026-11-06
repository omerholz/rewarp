import AppKit

enum AppIcon {
    static func install() {
        var candidates = [Bundle.main.url(forResource: "Rewarp", withExtension: "icns")]

        // swift run and the end-to-end harness launch an unbundled executable.
        // Resolve from the binary so this also works outside the repo's directory.
        if var directory = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            for _ in 0..<6 {
                directory = directory.deletingLastPathComponent()
                candidates.append(directory.appendingPathComponent("resources/icons/Rewarp.icns"))
            }
        }

        for case let url? in candidates {
            guard let image = NSImage(contentsOf: url) else { continue }
            NSApp.applicationIconImage = image
            return
        }
    }
}
