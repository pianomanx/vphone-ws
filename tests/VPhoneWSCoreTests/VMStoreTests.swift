import Testing
import Foundation
@testable import VPhoneWSCore

private func report(_ name: String, restore: RestoreInfo? = nil) -> VMReport {
    VMReport(name: name, cpuCount: 8, memoryMB: 8192, diskSizeBytes: 1, restoreInfo: restore)
}

@Test func rowDisplaysVersionsOrDash() {
    let ri = RestoreInfo(ios: .init(version: "27.0", build: "24A5380h"),
                         cloudOS: .init(version: "26.4", build: "23E5207q"))
    #expect(VMRow(report: report("a", restore: ri), isRunning: true).displayVersions == "iOS 27.0 · cloudOS 26.4")
    #expect(VMRow(report: report("b"), isRunning: false).displayVersions == "—")
}

@MainActor
@Test func refreshPopulatesRowsWithRunningState() async throws {
    let listJSON = "[{\"name\":\"a\",\"cpuCount\":8,\"memoryMB\":8192,\"diskSizeBytes\":1}," +
                   "{\"name\":\"b\",\"cpuCount\":8,\"memoryMB\":8192,\"diskSizeBytes\":1}]"
    let fake = FakeCLIRunner()
    let exe = URL(fileURLWithPath: "/usr/bin/vphone-cli")
    fake.stub(arguments: ["vm", "list", "--json", "--library-root", "/lib"],
              result: CLIResult(stdout: listJSON, stderr: "", exitCode: 0))
    fake.stub(arguments: ["-t", "--", "/lib/a/Disk.img"], result: CLIResult(stdout: "999\n", stderr: "", exitCode: 0))
    fake.stub(arguments: ["-t", "--", "/lib/b/Disk.img"], result: CLIResult(stdout: "", stderr: "", exitCode: 1))

    let client = VPhoneCLIClient(executable: exe, libraryRoot: "/lib", runner: fake)
    let store = VMStore(client: client, probe: RunningStateProbe(runner: fake), libraryRoot: "/lib")
    await store.refresh()

    #expect(store.rows.map(\.report.name) == ["a", "b"])
    #expect(store.rows.first(where: { $0.report.name == "a" })?.isRunning == true)
    #expect(store.rows.first(where: { $0.report.name == "b" })?.isRunning == false)
    #expect(store.loadError == nil)
}
