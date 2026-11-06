import CGhosttyVT
import Darwin
import Foundation
import os

/// The master side of a PTY. Whatever is using it keeps this alive, so it's closed
/// only once nothing can be. That matters twice over: on macOS, close() waits for a
/// read in progress on the same descriptor, which would deadlock with a child that
/// isn't printing, and a closed number can be reused by an unrelated file.
private final class Descriptor {
    let value: Int32

    init(_ value: Int32) {
        self.value = value
    }

    deinit {
        close(value)
    }
}

/// A child process on a pseudo-terminal, with a dedicated read thread.
public final class PTYProcess {
    public struct Launch {
        public var path: String
        public var argv: [String]
        public var environment: [String: String]
        public var workingDirectory: String?
        /// Set when this shell will report command boundaries. It proves a report
        /// came from the shell, and not from something a command printed.
        public var integrationToken: String?
        /// Opts into a single authenticated helper bootstrap for shells without
        /// a native socket builtin. Zsh keeps its direct, PID-bound handoff.
        public var integrationHelperPath: String?

        public var hasIntegration: Bool { integrationToken != nil }

        public init(path: String, argv: [String], environment: [String: String], workingDirectory: String?,
                    integrationToken: String? = nil, integrationHelperPath: String? = nil) {
            self.path = path
            self.argv = argv
            self.environment = environment
            self.workingDirectory = workingDirectory
            self.integrationToken = integrationToken
            self.integrationHelperPath = integrationHelperPath
        }
    }

    public let pid: pid_t
    private let descriptor: Descriptor
    /// Set once the child has been reaped, after which its pid could belong to
    /// something else and must not be signalled.
    private let hasExited = OSAllocatedUnfairLock(initialState: false)

    /// Writes get their own queue because a full PTY buffer blocks. Neither the
    /// main thread nor the read thread may ever stall on that.
    private let writeQueue = DispatchQueue(label: "rewarp.pty.write", qos: .userInteractive)

    public init(launch: Launch, cols: Int, rows: Int, widthPx: Int, heightPx: Int) throws {
        var outPid: pid_t = 0
        let env = launch.environment.map { "\($0.key)=\($0.value)" }
        let result = withCStringArray(launch.argv) { argv in
            withCStringArray(env) { envp in
                rewarp_pty_spawn(launch.path, argv, envp, launch.workingDirectory,
                                 UInt16(clamping: cols), UInt16(clamping: rows),
                                 UInt16(clamping: widthPx), UInt16(clamping: heightPx), &outPid)
            }
        }
        guard result >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        descriptor = Descriptor(result)
        pid = outPid
    }

    deinit {
        terminate()
    }

    /// Starts reading. `onData` runs on the read thread for each read, and
    /// `onExit` runs there once with the exit status when the child goes away.
    public func start(onData: @escaping (UnsafeRawBufferPointer) -> Void, onExit: @escaping (Int32) -> Void) {
        let descriptor = self.descriptor
        let hasExited = self.hasExited
        let pid = self.pid
        let reader = Thread {
            let fd = descriptor.value
            let capacity = 256 * 1024
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
            defer { buffer.deallocate() }
            while true {
                let n = read(fd, buffer, capacity)
                if n > 0 {
                    onData(UnsafeRawBufferPointer(start: buffer, count: n))
                } else if n == 0 || errno != EINTR {
                    break
                }
            }
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            hasExited.withLock { $0 = true }
            onExit(status)
        }
        reader.name = "rewarp.pty.read"
        reader.qualityOfService = .userInteractive
        reader.start()
    }

    public func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        let descriptor = self.descriptor
        writeQueue.async {
            let fd = descriptor.value
            bytes.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                    if n > 0 {
                        offset += n
                    } else if errno != EINTR && errno != EAGAIN {
                        return
                    }
                }
            }
        }
    }

    public func resize(cols: Int, rows: Int, widthPx: Int, heightPx: Int) {
        _ = rewarp_pty_resize(descriptor.value, UInt16(clamping: cols), UInt16(clamping: rows),
                              UInt16(clamping: widthPx), UInt16(clamping: heightPx))
    }

    /// Hangs up, as a closing terminal would. The shell passes that on to its jobs,
    /// and a program in the foreground gets it directly in case the shell is busy.
    public func terminate() {
        hasExited.withLock { exited in
            guard !exited else { return }
            let foreground = tcgetpgrp(descriptor.value)
            if foreground > 0 { kill(-foreground, SIGHUP) }
            kill(pid, SIGHUP)
        }
    }
}

private func withCStringArray<R>(_ strings: [String], _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
    let pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) } + [nil]
    defer { pointers.forEach { free($0) } }
    return pointers.withUnsafeBufferPointer { body($0.baseAddress!) }
}
