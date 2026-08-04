import Foundation

public struct CLIResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    /// True when the child was terminated by a signal (e.g. SIGKILL from AMFI)
    /// rather than exiting on its own. `exitCode` then holds the signal number.
    public let terminatedBySignal: Bool
    public var succeeded: Bool { exitCode == 0 }
    public init(stdout: String, stderr: String, exitCode: Int32, terminatedBySignal: Bool = false) {
        self.stdout = stdout; self.stderr = stderr; self.exitCode = exitCode
        self.terminatedBySignal = terminatedBySignal
    }
}

public protocol CLIRunner: Sendable {
    func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> CLIResult
}
