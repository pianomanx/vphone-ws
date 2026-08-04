import Foundation

public struct LaunchedProcess: Sendable { public let pid: Int32 }

public protocol ProcessLauncher: Sendable {
    func launch(executable: URL, arguments: [String], environment: [String: String]?) throws -> LaunchedProcess
}

public struct SystemProcessLauncher: ProcessLauncher {
    public init() {}
    public func launch(executable: URL, arguments: [String], environment: [String: String]?) throws -> LaunchedProcess {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        try process.run()
        return LaunchedProcess(pid: process.processIdentifier)
    }
}
