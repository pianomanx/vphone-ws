import Foundation

public enum VPhoneCLIError: Error, Equatable {
    case nonZeroExit(code: Int32, stderr: String)
    /// vphone-cli was terminated by a signal before it could run — almost always
    /// AMFI's SIGKILL because the amfidont allowlist daemon isn't active.
    case killedOnLaunch(signal: Int32)
    case decodeFailed(String)

    /// Plain-English, actionable text for surfacing in the UI.
    public var userMessage: String {
        switch self {
        case .killedOnLaunch(let signal):
            if signal == SIGKILL {
                return "vphone-cli was killed on launch (SIGKILL). The AMFI allowlist daemon "
                    + "(amfidont) isn't running — vphone-cli is a signed binary that AMFI blocks "
                    + "without it. Start it with `vphone-amfidont`, then reload."
            }
            return "vphone-cli was killed on launch by signal \(signal)."
        case .nonZeroExit(let code, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "vphone-cli exited with code \(code)."
                : "vphone-cli failed (exit \(code)): \(trimmed)"
        case .decodeFailed(let detail):
            return "Couldn't read vphone-cli output: \(detail)"
        }
    }
}

public struct VPhoneCLIClient: Sendable {
    let executable: URL
    let libraryRoot: String?
    let runner: CLIRunner

    public init(executable: URL, libraryRoot: String?, runner: CLIRunner) {
        self.executable = executable
        self.libraryRoot = libraryRoot
        self.runner = runner
    }

    public func listVMs() async throws -> [VMReport] {
        let data = try await runJSON(["vm", "list", "--json"])
        return try decode([VMReport].self, from: data)
    }

    public func info(name: String) async throws -> VMReport {
        let data = try await runJSON(["vm", "info", name, "--json"])
        return try decode(VMReport.self, from: data)
    }

    public func stop(name: String) async throws {
        _ = try await runText(["vm", "stop", name])
    }

    /// `fw catalog` takes no --library-root, so run it directly (not via runText).
    public func fetchCatalog() async throws -> FirmwareCatalog {
        let result = try await runner.run(
            executable: executable, arguments: ["fw", "catalog", "--json"], environment: nil)
        guard result.succeeded else { throw Self.failure(result) }
        return try decode(FirmwareCatalog.self, from: Data(result.stdout.utf8))
    }

    private func runJSON(_ base: [String]) async throws -> Data {
        let stdout = try await runText(base)
        return Data(stdout.utf8)
    }

    @discardableResult
    func runText(_ base: [String]) async throws -> String {
        var argv = base
        if let libraryRoot { argv += ["--library-root", libraryRoot] }
        let result = try await runner.run(executable: executable, arguments: argv, environment: nil)
        guard result.succeeded else { throw Self.failure(result) }
        return result.stdout
    }

    /// A signal-terminated child means the binary never ran (AMFI); anything else is a real exit code.
    static func failure(_ result: CLIResult) -> VPhoneCLIError {
        result.terminatedBySignal
            ? .killedOnLaunch(signal: result.exitCode)
            : .nonZeroExit(code: result.exitCode, stderr: result.stderr)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw VPhoneCLIError.decodeFailed(String(describing: error)) }
    }
}
