import Darwin
import Foundation
import Testing
import os
@testable import RewarpCore

@Suite("PTY descriptor isolation")
struct PTYIsolationTests {
    @Test("An inheritable descriptor above 255 cannot reach the executed child")
    func highDescriptor() throws {
        let original = open("/dev/null", O_RDONLY)
        #expect(original >= 0)
        guard original >= 0 else { return }
        defer { close(original) }
        let high = fcntl(original, F_DUPFD, 300)
        #expect(high >= 300)
        guard high >= 300 else { return }
        defer { close(high) }
        #expect(fcntl(high, F_GETFD) & FD_CLOEXEC == 0)

        // Python does not close inherited descriptors on startup. Testing the
        // executed interpreter avoids a shell closing the descriptor for us.
        let script = """
        import errno, os
        assert all(os.isatty(fd) for fd in (0, 1, 2))
        assert os.tcgetpgrp(0) == os.getpgrp()
        try:
            os.fstat(\(high))
        except OSError as error:
            assert error.errno == errno.EBADF
        else:
            raise AssertionError("inherited application descriptor")
        """
        let process = try PTYProcess(launch: .init(
            path: "/usr/bin/python3", argv: ["python3", "-c", script],
            environment: ["PATH": "/usr/bin:/bin"], workingDirectory: "/tmp"),
            cols: 80, rows: 24, widthPx: 800, heightPx: 480)
        let status = OSAllocatedUnfairLock<Int32?>(initialState: nil)
        let finished = DispatchSemaphore(value: 0)
        process.start(onData: { _ in }, onExit: { exitStatus in
            status.withLock { $0 = exitStatus }
            finished.signal()
        })
        defer { process.terminate() }
        #expect(finished.wait(timeout: .now() + 15) == .success)
        #expect(status.withLock { $0 } == 0)
    }
}
