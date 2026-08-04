import Foundation

public struct RunningStateProbe: Sendable {
    static let lsof = URL(fileURLWithPath: "/usr/sbin/lsof")
    let runner: CLIRunner

    public init(runner: CLIRunner) { self.runner = runner }

    public static func parsePIDs(_ stdout: String) -> [Int32] {
        stdout.split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// `lsof -t` exits non-zero when nothing matches — that means "not running", not an error.
    public func pids(diskImagePath: String) async throws -> [Int32] {
        let result = try await runner.run(
            executable: Self.lsof, arguments: ["-t", "--", diskImagePath], environment: nil)
        return Self.parsePIDs(result.stdout)
    }

    public func isRunning(diskImagePath: String) async throws -> Bool {
        try await !pids(diskImagePath: diskImagePath).isEmpty
    }

    /// First running process whose full command line contains `needle`. Used to
    /// find the GUI VM process (`vphone-cli --config …/config.plist`), which is
    /// distinct from the Virtualization XPC helper that actually holds Disk.img.
    public func firstPID(commandContaining needle: String) async -> Int32? {
        let out = (try? await runner.run(
            executable: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-Ao", "pid=,command="], environment: nil))?.stdout ?? ""
        for line in out.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains(needle),
                  let space = trimmed.firstIndex(of: " "),
                  let pid = Int32(trimmed[trimmed.startIndex..<space]) else { continue }
            return pid
        }
        return nil
    }
}
