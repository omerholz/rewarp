import Darwin
import Foundation

public enum ShellLaunch {
    /// The user's login shell from the password database. $SHELL is not
    /// reliable for an app launched from Finder. REWARP_SHELL overrides it, which
    /// is how tests reach shells that have no integration.
    public static func userShell() -> String {
        if let override = ProcessInfo.processInfo.environment["REWARP_SHELL"] { return override }
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        return "/bin/zsh"
    }

    /// Where a new session starts. $HOME wins, as it does for the shell itself.
    public static let homeDirectory =
        ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path

    /// A path as a shell prompt shows it, with the home directory as ~.
    public static func abbreviate(path: String) -> String {
        if path == homeDirectory { return "~" }
        return path.hasPrefix(homeDirectory + "/") ? "~" + path.dropFirst(homeDirectory.count) : path
    }

    /// Where the integration scripts live: in the app bundle when packaged, or
    /// in the repo for a development build.
    public static func integrationDirectory() -> URL? {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("shell-integration"))
        }
        // The real executable, because argv[0] can be relative to a directory the
        // user doesn't trust, and what's found here runs as shell startup files.
        if var directory = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            for _ in 0..<6 {
                directory = directory.deletingLastPathComponent()
                candidates.append(directory.appendingPathComponent("resources/shell-integration"))
            }
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The bridge is installed beside the executable, including SwiftPM's test
    /// bundle ancestors. Never resolve it through PATH or a working directory.
    public static func integrationHelper() -> URL? {
        // XCTest's main bundle is the Xcode test host, not the package test
        // bundle. The anchor locates the binary containing RewarpCore safely.
        let bundles = [Bundle.main, Bundle(for: ShellIntegrationBundleAnchor.self)]
        for bundle in bundles {
            guard var directory = bundle.executableURL?.resolvingSymlinksInPath() else { continue }
            for _ in 0..<6 {
                directory = directory.deletingLastPathComponent()
                let candidate = directory.appendingPathComponent("RewarpShellBridge")
                if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    public static func login(
        workingDirectory: String,
        shell: String = userShell(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        integrationDirectory integration: URL? = integrationDirectory()
    ) -> PTYProcess.Launch {
        let name = (shell as NSString).lastPathComponent

        var env = environment
        env["SHELL"] = shell
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Rewarp"
        env["TERM_PROGRAM_VERSION"] = RewarpVersion.string
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }

        var token: String?
        var bootstrapHelper: String?
        let integrationRoot = env["REWARP_SHELL_INTEGRATION"] == "none" ? nil : integration
        if name == "zsh", let integration = integrationRoot, let helper = integrationHelper() {
            // The script restores this straight away, so the user's shell never
            // sees a different ZDOTDIR.
            if let existing = env["ZDOTDIR"] { env["REWARP_USER_ZDOTDIR"] = existing }
            env["ZDOTDIR"] = integration.appendingPathComponent("zsh").path
            env["REWARP_SHELL_HELPER"] = helper.path
            // Never in the environment. The shell asks for it through TokenHandoff.
            token = UUID().uuidString
        } else if name == "bash", let integration = integrationRoot, let helper = integrationHelper() {
            let script = integration.appendingPathComponent("bash/bootstrap.bash")
            if FileManager.default.fileExists(atPath: script.path) {
                if let existing = env["ENV"] {
                    env["REWARP_USER_ENV"] = existing
                    env["REWARP_USER_ENV_SET"] = "1"
                }
                if let existing = env["POSIXLY_CORRECT"] {
                    env["REWARP_USER_POSIX"] = existing
                    env["REWARP_USER_POSIX_SET"] = "1"
                }
                env["ENV"] = script.path
                env["REWARP_SHELL_INIT"] = script.path
                env["REWARP_SHELL_HELPER"] = helper.path
                token = UUID().uuidString
                bootstrapHelper = helper.path
            }
        }

        // A leading dash in argv[0] is how a shell learns it is a login shell.
        let arguments = name == "bash" && token != nil ? ["--noprofile", "--posix", "-i"] : []
        return PTYProcess.Launch(path: shell, argv: ["-\(name)"] + arguments, environment: env,
                                 workingDirectory: workingDirectory, integrationToken: token,
                                 integrationHelperPath: bootstrapHelper)
    }
}

private final class ShellIntegrationBundleAnchor: NSObject {}
