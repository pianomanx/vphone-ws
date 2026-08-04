import Foundation

private final class ProcessOutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var exitCode: Int32 = 0
    private var bySignal = false

    func appendStdout(_ chunk: Data) {
        lock.lock(); stdout.append(chunk); lock.unlock()
    }

    func appendStderr(_ chunk: Data) {
        lock.lock(); stderr.append(chunk); lock.unlock()
    }

    func setTermination(code: Int32, bySignal: Bool) {
        lock.lock(); exitCode = code; self.bySignal = bySignal; lock.unlock()
    }

    func makeResult() -> CLIResult {
        lock.lock()
        defer { lock.unlock() }
        return CLIResult(
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self),
            exitCode: exitCode,
            terminatedBySignal: bySignal)
    }
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

public struct SystemCLIRunner: CLIRunner {
    public init() {}

    public func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> CLIResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let environment { process.environment = environment }
            let outPipe = Pipe(); let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let accumulator = ProcessOutputAccumulator()
            let resumeGuard = ResumeGuard()

            let group = DispatchGroup()
            group.enter()
            group.enter()
            group.enter()

            // `availableData` RAISES an ObjC exception on a read error (e.g. the fd
            // erroring when the child dies abnormally) — uncatchable in Swift, so it
            // aborts. `read(upToCount:)` THROWS instead; try? turns EOF/error into a
            // clean "done" without crashing.
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                guard let chunk = (try? handle.read(upToCount: 65_536)) ?? nil, !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    group.leave()
                    return
                }
                accumulator.appendStdout(chunk)
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                guard let chunk = (try? handle.read(upToCount: 65_536)) ?? nil, !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    group.leave()
                    return
                }
                accumulator.appendStderr(chunk)
            }
            process.terminationHandler = { proc in
                accumulator.setTermination(
                    code: proc.terminationStatus,
                    bySignal: proc.terminationReason == .uncaughtSignal)
                group.leave()
            }

            group.notify(queue: .global()) {
                let result = accumulator.makeResult()
                outPipe.fileHandleForReading.closeFile()
                errPipe.fileHandleForReading.closeFile()
                resumeGuard.resumeOnce {
                    continuation.resume(returning: result)
                }
            }

            do {
                try process.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                // `Process` never closed anything here since the child never launched.
                outPipe.fileHandleForReading.closeFile()
                errPipe.fileHandleForReading.closeFile()
                outPipe.fileHandleForWriting.closeFile()
                errPipe.fileHandleForWriting.closeFile()
                resumeGuard.resumeOnce {
                    continuation.resume(throwing: error)
                }
                // Balance the three enters above so `notify` still fires.
                group.leave()
                group.leave()
                group.leave()
            }
        }
    }
}
