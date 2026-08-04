import Testing
import Foundation
@testable import VPhoneWSCore

@Test func parsePIDsIgnoresBlankLines() {
    #expect(RunningStateProbe.parsePIDs("123\n456\n") == [123, 456])
    #expect(RunningStateProbe.parsePIDs("") == [])
    #expect(RunningStateProbe.parsePIDs("\n  \n789\n") == [789])
}

@Test func isRunningReflectsPIDPresence() async throws {
    let disk = "/Users/me/.vphone/VMs/a/Disk.img"
    let fake = FakeCLIRunner()
    fake.stub(arguments: ["-t", "--", disk], result: CLIResult(stdout: "4242\n", stderr: "", exitCode: 0))
    let probe = RunningStateProbe(runner: fake)
    #expect(try await probe.isRunning(diskImagePath: disk) == true)
}

@Test func isRunningFalseWhenLsofNonZeroWithNoHolders() async throws {
    let disk = "/Users/me/.vphone/VMs/b/Disk.img"
    let fake = FakeCLIRunner()
    fake.stub(arguments: ["-t", "--", disk], result: CLIResult(stdout: "", stderr: "", exitCode: 1))
    let probe = RunningStateProbe(runner: fake)
    #expect(try await probe.isRunning(diskImagePath: disk) == false)
}
