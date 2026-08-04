import Foundation
@testable import VPhoneWSCore

final class FakeProcessLauncher: ProcessLauncher, @unchecked Sendable {
    struct Call { let executable: URL; let arguments: [String]; let environment: [String: String]? }
    private(set) var calls: [Call] = []
    let stubPID: Int32
    init(stubPID: Int32 = 1) { self.stubPID = stubPID }

    func launch(executable: URL, arguments: [String], environment: [String: String]?) throws -> LaunchedProcess {
        calls.append(Call(executable: executable, arguments: arguments, environment: environment))
        return LaunchedProcess(pid: stubPID)
    }
}
