import Testing
import Foundation
@testable import VPhoneWSCore

private let exe = URL(fileURLWithPath: "/usr/bin/vphone-cli")

private func client(_ runner: FakeCLIRunner) -> VPhoneCLIClient {
    VPhoneCLIClient(executable: exe, libraryRoot: nil, runner: runner)
}

@Test func setConfigOnlyIncludesGivenFields() async throws {
    let r = FakeCLIRunner()
    r.stub(arguments: ["vm", "config", "a", "--cpu", "6", "--network", "bridged"],
           result: CLIResult(stdout: "updated", stderr: "", exitCode: 0))
    try await client(r).setConfig(name: "a", cpu: 6, memoryMB: nil, network: "bridged")
    #expect(r.calls[0].arguments == ["vm", "config", "a", "--cpu", "6", "--network", "bridged"])
}

@Test func deletePassesForce() async throws {
    let r = FakeCLIRunner()
    r.stub(arguments: ["vm", "delete", "a", "--force"], result: CLIResult(stdout: "deleted a", stderr: "", exitCode: 0))
    try await client(r).delete(name: "a")
    #expect(r.calls[0].arguments == ["vm", "delete", "a", "--force"])
}

@Test func cloneAndRenamePassBothNames() async throws {
    let r = FakeCLIRunner()
    r.stub(arguments: ["vm", "clone", "a", "b"], result: CLIResult(stdout: "cloned", stderr: "", exitCode: 0))
    r.stub(arguments: ["vm", "rename", "b", "c"], result: CLIResult(stdout: "renamed", stderr: "", exitCode: 0))
    try await client(r).clone(name: "a", to: "b")
    try await client(r).rename(name: "b", to: "c")
    #expect(r.calls.map(\.arguments) == [["vm","clone","a","b"], ["vm","rename","b","c"]])
}
