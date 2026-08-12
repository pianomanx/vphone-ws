import Foundation
import Testing
@testable import VPhoneWSCore

private final class StreamCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: Int32 = 0
    private var lines: [String] = []

    func recordStart(_ pid: Int32) { lock.lock(); self.pid = pid; lock.unlock() }
    func recordLine(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }

    var startedPID: Int32 { lock.lock(); defer { lock.unlock() }; return pid }
    var seenLines: [String] { lock.lock(); defer { lock.unlock() }; return lines }
}

@Test func fakeStreamerEmitsLinesThenExit() async throws {
    let fake = FakeStreamingRunner(lines: ["=== Prepare ===", "[+] done"], exitCode: 0, stubPID: 9)
    let collector = StreamCollector()
    let code = try await fake.run(executable: URL(fileURLWithPath: "/x"), arguments: [], environment: nil,
                                   onStart: { collector.recordStart($0) }, onEvent: { if case .line(let s) = $0 { collector.recordLine(s) } })
    #expect(collector.startedPID == 9)
    #expect(collector.seenLines == ["=== Prepare ===", "[+] done"])
    #expect(code == 0)
}

@Test func systemStreamerEchoesLines() async throws {
    let runner = SystemStreamingRunner()
    let collector = StreamCollector()
    let code = try await runner.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["one\ntwo"],
                                     environment: nil, onStart: { collector.recordStart($0) }, onEvent: { if case .line(let s) = $0 { collector.recordLine(s) } })
    #expect(code == 0)
    #expect(collector.seenLines.contains("one"))
    #expect(collector.seenLines.contains("two"))
    #expect(collector.startedPID > 0)
}

@Test(.timeLimit(.minutes(1)))
func systemStreamerHandlesLargeOutputWithoutDeadlockOrTruncation() async throws {
    let runner = SystemStreamingRunner()
    let collector = StreamCollector()
    let code = try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "yes X | head -c 200000"],
        environment: nil,
        onStart: { collector.recordStart($0) },
        onEvent: { if case .line(let s) = $0 { collector.recordLine(s) } })

    let lines = collector.seenLines
    let totalBytes = lines.reduce(0) { $0 + $1.utf8.count + 1 }
    #expect(lines.count == 100_000)
    #expect(lines.allSatisfy { $0 == "X" })
    #expect(totalBytes == 200_000)
    #expect(code == 0)
}

@Test(.timeLimit(.minutes(1)))
func systemStreamerThrowsPromptlyForInvalidExecutable() async throws {
    let runner = SystemStreamingRunner()
    await #expect(throws: (any Error).self) {
        _ = try await runner.run(
            executable: URL(fileURLWithPath: "/nonexistent/definitely-not-a-binary"),
            arguments: [], environment: nil, onStart: { _ in }, onEvent: { _ in })
    }
}

@Test(.timeLimit(.minutes(1)))
func systemStreamerFlushesTrailingLineWithoutNewline() async throws {
    let runner = SystemStreamingRunner()
    let collector = StreamCollector()
    let code = try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "printf 'line-one\\nno-newline-tail'"],
        environment: nil,
        onStart: { collector.recordStart($0) },
        onEvent: { if case .line(let s) = $0 { collector.recordLine(s) } })

    #expect(collector.seenLines == ["line-one", "no-newline-tail"])
    #expect(code == 0)
}

@Test(.timeLimit(.minutes(1)))
func systemStreamerCapturesStderrThroughMergedPipe() async throws {
    let runner = SystemStreamingRunner()
    let collector = StreamCollector()
    let code = try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "echo out; echo err 1>&2"],
        environment: nil,
        onStart: { collector.recordStart($0) },
        onEvent: { if case .line(let s) = $0 { collector.recordLine(s) } })

    #expect(collector.seenLines.contains("out"))
    #expect(collector.seenLines.contains("err"))
    #expect(code == 0)
}

@Test(.timeLimit(.minutes(1)))
func systemStreamerStripsAnsiEscapes() async throws {
    // Progress bars emit color / erase-line escapes; the log is plain text, so
    // they must be stripped, leaving the visible characters.
    let runner = SystemStreamingRunner()
    let collector = StreamCollector()
    let code = try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "printf 'a\\033[31mRED\\033[0m\\033[Kb\\n'"],
        environment: nil,
        onStart: { _ in },
        onEvent: { if case .line(let s) = $0 { collector.recordLine(s) } })

    #expect(code == 0)
    #expect(collector.seenLines == ["aREDb"])
}

@Test func withHomebrewPathAppendsBrewDirsWithoutDuplicating() {
    let augmented = SystemStreamingRunner.withHomebrewPath(["PATH": "/usr/bin:/bin"])
    #expect(augmented["PATH"] == "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin")

    let idempotent = SystemStreamingRunner.withHomebrewPath(["PATH": "/opt/homebrew/bin:/usr/bin"])
    #expect(idempotent["PATH"] == "/opt/homebrew/bin:/usr/bin:/usr/local/bin")
}

@Test(.timeLimit(.minutes(1)))
func systemStreamerGivesChildHomebrewOnPath() async throws {
    let runner = SystemStreamingRunner()
    let collector = StreamCollector()
    let code = try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "echo $PATH"],
        environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
        onStart: { _ in },
        onEvent: { if case .line(let s) = $0 { collector.recordLine(s) } })
    #expect(code == 0)
    #expect(collector.seenLines.contains { $0.split(separator: ":").contains("/opt/homebrew/bin") })
}

private final class TimedRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    private var _times: [TimeInterval] = []
    private let start = Date()
    func recordLine(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        _lines.append(s); _times.append(Date().timeIntervalSince(start))
    }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
    // Wall-clock between the first and last line — factors out process start-up.
    var spread: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        guard let f = _times.first, let l = _times.last else { return 0 }
        return l - f
    }
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [StreamEvent] = []
    func record(_ e: StreamEvent) { lock.lock(); _events.append(e); lock.unlock() }
    var events: [StreamEvent] { lock.lock(); defer { lock.unlock() }; return _events }
}

@Test(.timeLimit(.minutes(1)))
func systemStreamerDeliversLinesLiveNotAtExit() async throws {
    // Python line-buffers stdout to a TTY (our PTY) but block-buffers to a pipe.
    // On a pipe all three lines would arrive together at exit (spread ~0); over
    // the PTY they must arrive ~0.3s apart as they're printed.
    let runner = SystemStreamingRunner()
    let rec = TimedRecorder()
    let code = try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "printf 'a\\n'; sleep 0.3; printf 'b\\n'; sleep 0.3; printf 'c\\n'"],
        environment: nil,
        onStart: { _ in },
        onEvent: { if case .line(let s) = $0 { rec.recordLine(s) } })
    #expect(code == 0)
    #expect(rec.lines == ["a", "b", "c"])
    #expect(rec.spread > 0.4)   // arrived spread out (live), not batched at exit
}

@Test(.timeLimit(.minutes(1)))
func systemStreamerTreatsCarriageReturnAsLiveOverwrite() async throws {
    // A progress bar overwrites one line via \r. Those must be live `.update`s,
    // not committed `.line`s — otherwise the log shows duplicate progress lines.
    let runner = SystemStreamingRunner()
    let rec = EventRecorder()
    let code = try await runner.run(
        executable: URL(fileURLWithPath: "/usr/bin/python3"),
        arguments: ["-c", "import sys\nfor p in ['10%','20%','30%']:\n    sys.stdout.write(p+'\\r'); sys.stdout.flush()\nsys.stdout.write('done\\n')"],
        environment: nil,
        onStart: { _ in },
        onEvent: { rec.record($0) })
    let committed = rec.events.compactMap { if case .line(let s) = $0 { return s } else { return nil } }
    let updates = rec.events.compactMap { if case .update(let s) = $0 { return s } else { return nil } }
    #expect(code == 0)
    #expect(committed == ["done"])                          // only the real newline commits
    #expect(updates.contains("10%") && updates.contains("20%"))  // progress = live overwrites
}
