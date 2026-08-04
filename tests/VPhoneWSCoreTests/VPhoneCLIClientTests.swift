import Testing
import Foundation
@testable import VPhoneWSCore

private let exe = URL(fileURLWithPath: "/usr/bin/vphone-cli")

@Test func listAssemblesArgvAndDecodes() async throws {
    let fake = FakeCLIRunner()
    fake.stub(arguments: ["vm", "list", "--json", "--library-root", "/lib"],
              result: CLIResult(stdout: "[{\"name\":\"a\",\"cpuCount\":8,\"memoryMB\":8192,\"diskSizeBytes\":1}]",
                                stderr: "", exitCode: 0))
    let client = VPhoneCLIClient(executable: exe, libraryRoot: "/lib", runner: fake)
    let vms = try await client.listVMs()
    #expect(vms.map(\.name) == ["a"])
    #expect(fake.calls[0].arguments == ["vm", "list", "--json", "--library-root", "/lib"])
}

@Test func infoAssemblesArgvWithExplicitName() async throws {
    let fake = FakeCLIRunner()
    fake.stub(arguments: ["vm", "info", "a", "--json"],
              result: CLIResult(stdout: "{\"name\":\"a\",\"cpuCount\":8,\"memoryMB\":8192,\"diskSizeBytes\":1}",
                                stderr: "", exitCode: 0))
    let client = VPhoneCLIClient(executable: exe, libraryRoot: nil, runner: fake)
    let vm = try await client.info(name: "a")
    #expect(vm.name == "a")
}

@Test func nonZeroExitThrows() async throws {
    let fake = FakeCLIRunner()
    fake.stub(arguments: ["vm", "list", "--json"],
              result: CLIResult(stdout: "", stderr: "boom", exitCode: 1))
    let client = VPhoneCLIClient(executable: exe, libraryRoot: nil, runner: fake)
    await #expect(throws: VPhoneCLIError.nonZeroExit(code: 1, stderr: "boom")) {
        _ = try await client.listVMs()
    }
}

@Test func signalTerminationThrowsKilledOnLaunch() async throws {
    let fake = FakeCLIRunner()
    fake.stub(arguments: ["vm", "list", "--json"],
              result: CLIResult(stdout: "", stderr: "", exitCode: 9, terminatedBySignal: true))
    let client = VPhoneCLIClient(executable: exe, libraryRoot: nil, runner: fake)
    await #expect(throws: VPhoneCLIError.killedOnLaunch(signal: 9)) {
        _ = try await client.listVMs()
    }
}

@Test func killedOnLaunchMessageNamesAmfidont() {
    let msg = VPhoneCLIError.killedOnLaunch(signal: SIGKILL).userMessage
    #expect(msg.contains("amfidont"))
    #expect(msg.contains("vphone-amfidont"))
}
