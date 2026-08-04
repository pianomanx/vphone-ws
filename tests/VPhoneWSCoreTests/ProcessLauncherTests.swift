import Testing
import Foundation
@testable import VPhoneWSCore

@Test func fakeLauncherRecordsAndReturnsPID() throws {
    let fake = FakeProcessLauncher(stubPID: 4242)
    let p = try fake.launch(executable: URL(fileURLWithPath: "/x"), arguments: ["vm", "launch", "a"], environment: nil)
    #expect(p.pid == 4242)
    #expect(fake.calls.count == 1)
    #expect(fake.calls[0].arguments == ["vm", "launch", "a"])
}

@Test func systemLauncherStartsProcessWithoutWaiting() throws {
    let launcher = SystemProcessLauncher()
    let p = try launcher.launch(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], environment: nil)
    #expect(p.pid > 0)
    kill(p.pid, SIGTERM)
}
