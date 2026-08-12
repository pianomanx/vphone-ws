import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A committed line (terminated by `\n`) or a live overwrite of the current
/// line (terminated by `\r`, as terminal progress bars do).
public enum StreamEvent: Sendable, Equatable {
    case line(String)
    case update(String)
}

public protocol StreamingRunner: Sendable {
    func run(executable: URL, arguments: [String], environment: [String: String]?,
             onStart: @escaping @Sendable (Int32) -> Void,
             onEvent: @escaping @Sendable (StreamEvent) -> Void) async throws -> Int32
}

/// Splits a raw byte stream applying minimal terminal semantics: `\n` commits a
/// line, a lone `\r` emits the current text as a live overwrite (progress bars),
/// and `\r\n` is a single commit. State survives chunk boundaries.
private final class TerminalSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var partial = Data()
    private var pendingCR = false
    private let onEvent: @Sendable (StreamEvent) -> Void

    init(onEvent: @escaping @Sendable (StreamEvent) -> Void) {
        self.onEvent = onEvent
    }

    func append(_ chunk: Data) {
        lock.lock()
        var events: [StreamEvent] = []
        for byte in chunk {
            if pendingCR {
                pendingCR = false
                if byte == 0x0A {
                    events.append(.line(Self.decode(partial)))
                    partial.removeAll(keepingCapacity: true)
                    continue
                }
                events.append(.update(Self.decode(partial)))
                partial.removeAll(keepingCapacity: true)
            }
            switch byte {
            case 0x0D: pendingCR = true
            case 0x0A:
                events.append(.line(Self.decode(partial)))
                partial.removeAll(keepingCapacity: true)
            default: partial.append(byte)
            }
        }
        lock.unlock()
        for e in events { onEvent(e) }
    }

    func flush() {
        lock.lock()
        pendingCR = false
        let remainder = partial
        partial.removeAll()
        lock.unlock()
        if !remainder.isEmpty { onEvent(.line(Self.decode(remainder))) }
    }

    private static func decode(_ d: Data) -> String {
        stripANSI(String(decoding: d, as: UTF8.self))
    }

    /// The log is a plain text view, not a terminal — drop ANSI escape sequences
    /// (color, erase-line, cursor moves) that progress bars emit, keeping the
    /// visible text and bar glyphs. Escape sequences never contain \r/\n, so a
    /// full sequence is always contained in one emitted line/update.
    static func stripANSI(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        var out = String()
        out.reserveCapacity(s.count)
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            guard chars[i] == "\u{1B}" else { out.append(chars[i]); i += 1; continue }
            i += 1
            guard i < chars.count else { break }
            if chars[i] == "[" {              // CSI: ESC [ … final byte @-~
                i += 1
                while i < chars.count {
                    let a = chars[i].asciiValue
                    i += 1
                    if let a, a >= 0x40, a <= 0x7E { break }
                }
            } else if chars[i] == "]" {       // OSC: ESC ] … BEL or ST (ESC \)
                i += 1
                while i < chars.count {
                    if chars[i] == "\u{07}" { i += 1; break }
                    if chars[i] == "\u{1B}", i + 1 < chars.count, chars[i + 1] == "\\" { i += 2; break }
                    i += 1
                }
            } else {                          // other 2-char escape
                i += 1
            }
        }
        return out
    }
}

private final class ExitCodeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int32 = 0
    func set(_ code: Int32) { lock.lock(); value = code; lock.unlock() }
    func get() -> Int32 { lock.lock(); defer { lock.unlock() }; return value }
}

private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resumeOnce(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        body()
    }
}

public struct SystemStreamingRunner: StreamingRunner {
    public init() {}

    /// A Finder/launchd-launched app gets a minimal PATH without Homebrew, so
    /// bsdtar's `--zstd` (which execs external `zstd`) fails on export. Append
    /// the Homebrew bin dirs, keeping system binaries first.
    static func withHomebrewPath(_ env: [String: String]) -> [String: String] {
        var env = env
        var entries = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":", omittingEmptySubsequences: true).map(String.init)
        for dir in ["/opt/homebrew/bin", "/usr/local/bin"] where !entries.contains(dir) {
            entries.append(dir)
        }
        env["PATH"] = entries.joined(separator: ":")
        return env
    }

    public func run(executable: URL, arguments: [String], environment: [String: String]?,
                    onStart: @escaping @Sendable (Int32) -> Void,
                    onEvent: @escaping @Sendable (StreamEvent) -> Void) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            // Run the child under a pseudo-terminal, not a pipe: programs
            // line-buffer stdout to a TTY but BLOCK-buffer it to a pipe, so a
            // pipe only surfaces output at ~8KB boundaries / on exit. A PTY
            // makes isatty(stdout) true → output flushes live.
            var master: Int32 = 0
            var slave: Int32 = 0
            var win = winsize(ws_row: 60, ws_col: 220, ws_xpixel: 0, ws_ypixel: 0)
            // Raw mode: keep isatty() true but make the PTY a transparent byte
            // conduit — no CR translation, echo, or line editing.
            var term = termios()
            cfmakeraw(&term)
            guard openpty(&master, &slave, nil, &term, &win) == 0 else {
                continuation.resume(throwing: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
                return
            }
            let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)

            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            var env = environment ?? ProcessInfo.processInfo.environment
            if env["TERM"] == nil { env["TERM"] = "xterm-256color" }
            // Python (pmd3 restore bridge) block-buffers stdout even on a TTY;
            // force it unbuffered so its lines stream live like everything else.
            env["PYTHONUNBUFFERED"] = "1"
            env = Self.withHomebrewPath(env)
            process.environment = env
            process.standardOutput = slaveHandle
            process.standardError = slaveHandle
            process.standardInput = FileHandle.nullDevice

            let splitter = TerminalSplitter(onEvent: onEvent)
            let exitCodeBox = ExitCodeBox()
            let resumeGuard = ResumeGuard()

            let group = DispatchGroup()
            group.enter()  // read thread
            group.enter()  // process termination

            // A GCD readability source over a PTY master fd coalesces and only
            // fires at EOF; a dedicated blocking read loop returns promptly on
            // each write (raw mode → no line-discipline hold), so output is live.
            let readThread = Thread {
                let size = 65_536
                let buf = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 1)
                defer { buf.deallocate() }
                while true {
                    let n = read(master, buf, size)
                    if n > 0 {
                        splitter.append(Data(bytes: buf, count: n))
                    } else {
                        break  // 0 = EOF, -1 = error (EIO once the slave closes)
                    }
                }
                group.leave()
            }
            readThread.stackSize = 1 << 20

            process.terminationHandler = { proc in
                exitCodeBox.set(proc.terminationStatus)
                group.leave()
            }

            group.notify(queue: .global()) {
                splitter.flush()
                close(master)
                resumeGuard.resumeOnce {
                    continuation.resume(returning: exitCodeBox.get())
                }
            }

            do {
                try process.run()
                onStart(process.processIdentifier)
                readThread.start()
                // Parent drops its slave copy so the master read hits EOF when
                // the child (last slave holder) exits.
                try? slaveHandle.close()
            } catch {
                // Don't close master here — the two leaves below fire `notify`,
                // which owns the master close. Closing it twice can clobber an
                // fd another (parallel) run just reused.
                try? slaveHandle.close()
                resumeGuard.resumeOnce {
                    continuation.resume(throwing: error)
                }
                group.leave()  // read thread never started
                group.leave()  // termination never fires
            }
        }
    }
}
