import Darwin
import Foundation

/// A private configuration wrapper keeps Fish's native initialization and
/// universal-variable engine enabled while claiming the credential before user
/// conf.d files. No credential is written to these files.
final class FishIntegration {
    let directory: URL

    init?(environment: [String: String]) {
        let manager = FileManager.default
        let home = environment["HOME"] ?? ShellLaunch.homeDirectory
        let configRoot = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? (home as NSString).appendingPathComponent(".config")
        let user = URL(fileURLWithPath: configRoot).appendingPathComponent("fish")
        directory = manager.temporaryDirectory.appendingPathComponent("rewarp-fish-\(UUID().uuidString)")
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
            let fish = directory.appendingPathComponent("fish")
            let snippets = fish.appendingPathComponent("conf.d")
            try manager.createDirectory(at: snippets, withIntermediateDirectories: true)
            try manager.createDirectory(at: user, withIntermediateDirectories: true)
            // Fish resolves this symlink before atomically updating universal
            // variables, preserving synchronization with ordinary Fish sessions.
            let variables = user.appendingPathComponent("fish_variables")
            let fd = open(variables.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            if fd >= 0 { close(fd) }
            try manager.createSymbolicLink(at: fish.appendingPathComponent("fish_variables"),
                                           withDestinationURL: variables)
            // Mask user filenames here, then source their real paths from the
            // bootstrap. Fish's own loop still applies user > system > vendor
            // basename precedence, and relative plugin paths remain correct.
            let files = (try? manager.contentsOfDirectory(atPath: user.appendingPathComponent("conf.d").path)) ?? []
            for name in files where name.hasSuffix(".fish") && !name.hasPrefix(".") {
                try manager.createSymbolicLink(at: snippets.appendingPathComponent(name),
                                               withDestinationURL: URL(fileURLWithPath: "/dev/null"))
            }
            let name = "rewarp-bootstrap-\(UUID().uuidString).fish"
            try "source \"$REWARP_SHELL_INIT/bootstrap.fish\"\n".write(
                to: snippets.appendingPathComponent(name), atomically: true, encoding: .utf8)
            try "if test -r \"$_rewarp_user_config/config.fish\"; source \"$_rewarp_user_config/config.fish\"; end\n".write(
                to: fish.appendingPathComponent("config.fish"), atomically: true, encoding: .utf8)
        } catch {
            try? manager.removeItem(at: directory)
            return nil
        }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}
