import Foundation
import Testing
@testable import VPhoneWSCore

private let exe = URL(fileURLWithPath: "/usr/bin/vphone-cli")

@MainActor
@Test func runAdvancesStagesAndSucceeds() async {
    let runner = FakeStreamingRunner(
        lines: ["=== Prepare ===", "[*] downloading", "=== Restore phase ===", "[+] ok"],
        exitCode: 0)
    let task = TaskModel(title: "Create a", plannedStages: ["Prepare", "Restore phase"])
    await task.run(executable: exe, arguments: ["vm", "create", "a"], runner: runner)
    // Every planned stage reads done once the task succeeds — nothing left "current".
    #expect(task.completedStages == ["Prepare", "Restore phase"])
    #expect(task.currentStage == nil)
    #expect(task.logLines.contains("[*] downloading"))
    #expect(task.status == .succeeded)
}

@MainActor
@Test func mapsCreateBannersToMockupChips() async {
    let runner = FakeStreamingRunner(
        lines: ["=== vm new ===", "=== fw prepare ===", "=== fw patch ===",
                "=== Restore phase ===", "=== CFW install (host-mount) ===",
                "=== First boot ===", "=== Done ==="],
        exitCode: 0)
    let task = TaskModel(
        title: "Create a",
        plannedStages: VPhoneCommandBuilder.createStages,
        stageMap: VPhoneCommandBuilder.createStageMap)
    await task.run(executable: exe, arguments: [], runner: runner)
    // "vm new" / "Done" are unmapped → no chip; mapped banners drive the chips in order.
    #expect(task.completedStages == ["Prepare", "Patch", "Restore", "Install CFW", "First boot"])
    #expect(task.currentStage == nil)
    #expect(task.status == .succeeded)
}

@MainActor
@Test func groupsOutputIntoPerStageSegments() async {
    let runner = FakeStreamingRunner(
        lines: ["preflight ok", "=== fw prepare ===", "[*] downloading", "[+] merged",
                "=== fw patch ===", "[+] applied 52"],
        exitCode: 0)
    let task = TaskModel(
        title: "Create a",
        plannedStages: VPhoneCommandBuilder.createStages,
        stageMap: VPhoneCommandBuilder.createStageMap)
    await task.run(executable: exe, arguments: [], runner: runner)
    // Leading output → "Starting up"; each banner opens its own grouped segment.
    let titles = task.segments.map(\.title)
    let allDone = task.segments.allSatisfy { $0.isDone }
    #expect(titles == ["Starting up", "Prepare", "Patch"])
    #expect(task.segments[0].lines == ["preflight ok"])
    #expect(task.segments[1].lines == ["[*] downloading", "[+] merged"])
    #expect(task.segments[2].lines == ["[+] applied 52"])
    #expect(allDone)
}

@MainActor
@Test func nonZeroExitMarksFailed() async {
    let runner = FakeStreamingRunner(lines: ["[-] boom"], exitCode: 3)
    let task = TaskModel(title: "Create a", plannedStages: [])
    await task.run(executable: exe, arguments: [], runner: runner)
    #expect(task.status == .failed(3))
}
