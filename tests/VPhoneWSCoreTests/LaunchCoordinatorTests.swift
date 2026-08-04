import Testing
import Foundation
@testable import VPhoneWSCore

private let exe = URL(fileURLWithPath: "/usr/bin/vphone-cli")

@MainActor
@Test func launchSpawnsWithExplicitNameAndLibraryRoot() throws {
    let launcher = FakeProcessLauncher(stubPID: 77)
    let runner = FakeCLIRunner()
    let client = VPhoneCLIClient(executable: exe, libraryRoot: "/lib", runner: runner)
    let coord = LaunchCoordinator(
        executable: exe, libraryRoot: "/lib", launcher: launcher, client: client,
        probe: RunningStateProbe(runner: runner))
    try coord.launch(name: "a")
    #expect(launcher.calls[0].arguments == ["vm", "launch", "a", "--library-root", "/lib"])
}

@MainActor
@Test func stopRunsVmStop() async throws {
    let runner = FakeCLIRunner()
    runner.stub(arguments: ["vm", "stop", "a", "--library-root", "/lib"],
                result: CLIResult(stdout: "a: stopped", stderr: "", exitCode: 0))
    let client = VPhoneCLIClient(executable: exe, libraryRoot: "/lib", runner: runner)
    let coord = LaunchCoordinator(
        executable: exe, libraryRoot: "/lib", launcher: FakeProcessLauncher(stubPID: 5),
        client: client, probe: RunningStateProbe(runner: runner))
    try await coord.stop(name: "a")
    #expect(runner.calls.contains { $0.arguments == ["vm", "stop", "a", "--library-root", "/lib"] })
}
