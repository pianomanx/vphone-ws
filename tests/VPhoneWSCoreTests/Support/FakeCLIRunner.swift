import Foundation
@testable import VPhoneWSCore

final class FakeCLIRunner: CLIRunner, @unchecked Sendable {
    struct Call { let executable: URL; let arguments: [String]; let environment: [String: String]? }
    private(set) var calls: [Call] = []
    private var stubs: [[String]: CLIResult] = [:]

    func stub(arguments: [String], result: CLIResult) { stubs[arguments] = result }

    func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> CLIResult {
        calls.append(Call(executable: executable, arguments: arguments, environment: environment))
        guard let result = stubs[arguments] else {
            return CLIResult(stdout: "", stderr: "no stub for \(arguments)", exitCode: 127)
        }
        return result
    }
}
