import Foundation

public enum GitInfo {
    /// The git directory for a path, reading the `.git` file that worktrees and
    /// submodules have in place of a directory.
    public static func directory(from path: String) -> URL? {
        var directory = URL(fileURLWithPath: path)
        let manager = FileManager.default
        while true {
            let git = directory.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: git.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue { return git }
                guard let text = try? String(contentsOf: git, encoding: .utf8) else { return nil }
                let prefix = "gitdir: "
                let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.hasPrefix(prefix) else { return nil }
                return URL(fileURLWithPath: String(line.dropFirst(prefix.count)), relativeTo: directory)
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return nil }
            directory = parent
        }
    }

    /// Where refs live. A linked worktree shares them with its main repository.
    public static func commonDirectory(from path: String) -> URL? {
        guard let git = directory(from: path) else { return nil }
        let pointer = git.appendingPathComponent("commondir")
        guard let text = try? String(contentsOf: pointer, encoding: .utf8) else { return git }
        return URL(fileURLWithPath: text.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: git)
    }

    /// The checked-out branch for a directory, from `HEAD`. Reading the file
    /// directly avoids starting a process for every prompt.
    public static func branch(at path: String) -> String? {
        guard let git = directory(from: path),
              let head = try? String(contentsOf: git.appendingPathComponent("HEAD"), encoding: .utf8) else {
            return nil
        }
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : String(line.prefix(7))
    }
}
