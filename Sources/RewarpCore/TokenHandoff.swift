import Darwin
import Foundation

/// How the shell gets its report token.
///
/// The environment can't carry it: a command can read a shell's starting environment
/// through `ps -E`, and leaving it there for `exec zsh` would give it to every command.
/// So the shell asks for it here, once when it starts and again whenever it replaces
/// itself. The kernel says which process connected. `exec` keeps the pid and a command
/// has one of its own, so the pane's shell gets the token and a command that asks gets
/// nothing.
final class TokenHandoff {
    let path: String
    private let listener: Int32
    private var source: DispatchSourceRead?

    /// Tried in turn, because a shell with no token has no blocks. A TMPDIR left over
    /// from wherever the app was launched can be gone, or too long for a socket path.
    /// NSTemporaryDirectory() ignores it, which is how a test keeps this to itself.
    /// Other users can connect to a socket in /tmp, but none of them is the shell.
    private static var directories: [String] {
        [ProcessInfo.processInfo.environment["TMPDIR"], NSTemporaryDirectory(), "/tmp"].compactMap { $0 }
    }

    /// Nil if the socket can't be made anywhere. The shell then gets no token, so the
    /// pane ends up a plain terminal, as with a shell that has no integration.
    init?(directories: [String] = TokenHandoff.directories) {
        for directory in directories {
            let path = (directory as NSString).appendingPathComponent("rewarp-\(UUID().uuidString.prefix(8)).sock")
            if let listener = Self.makeListener(at: path) {
                self.path = path
                self.listener = listener
                return
            }
        }
        return nil
    }

    private static func makeListener(at path: String) -> Int32? {
        var address = sockaddr_un()
        let bytes = path.utf8CString.map { UInt8(bitPattern: $0) }
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_family = sa_family_t(AF_UNIX)

        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { return nil }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        // Close-on-exec, so no command can accept the shell's connection itself.
        // Non-blocking, so a client that's gone by the time of accept can't stall the queue.
        guard bound == 0, fcntl(listener, F_SETFD, FD_CLOEXEC) == 0, fcntl(listener, F_SETFL, O_NONBLOCK) == 0,
              listen(listener, 8) == 0 else {
            close(listener)
            if bound == 0 { unlink(path) }
            return nil
        }
        return listener
    }

    deinit {
        if let source {
            source.cancel()
        } else {
            close(listener)
            unlink(path)
        }
    }

    /// Answers only `shell`, from now until this object goes away. The shell can
    /// connect before this runs, since the listener is up by the time it starts, and
    /// it then waits in the backlog.
    func serve(token: String, shell: pid_t) {
        let listener = self.listener
        let path = self.path
        // Not a background queue: every new shell waits on this before it can start.
        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: .global(qos: .userInitiated))
        source.setEventHandler {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }

            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

            var peer: pid_t = 0
            var length = socklen_t(MemoryLayout<pid_t>.size)
            guard getsockopt(client, SOL_LOCAL, LOCAL_PEERPID, &peer, &length) == 0, peer == shell else { return }
            let reply = Array((token + "\n").utf8)
            _ = write(client, reply, reply.count)
        }
        source.setCancelHandler {
            close(listener)
            unlink(path)
        }
        source.resume()
        self.source = source
    }
}
