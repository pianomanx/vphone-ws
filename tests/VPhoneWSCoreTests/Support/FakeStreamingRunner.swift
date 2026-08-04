import Foundation
@testable import VPhoneWSCore

final class FakeStreamingRunner: StreamingRunner, @unchecked Sendable {
    let lines: [String]
    let exitCode: Int32
    let stubPID: Int32

    init(lines: [String], exitCode: Int32, stubPID: Int32 = 1) {
        self.lines = lines
        self.exitCode = exitCode
        self.stubPID = stubPID
    }

    func run(executable: URL, arguments: [String], environment: [String: String]?,
             onStart: @escaping @Sendable (Int32) -> Void,
             onEvent: @escaping @Sendable (StreamEvent) -> Void) async throws -> Int32 {
        onStart(stubPID)
        for line in lines { onEvent(.line(line)) }
        return exitCode
    }
}
