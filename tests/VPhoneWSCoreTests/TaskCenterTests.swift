import Foundation
import Testing
@testable import VPhoneWSCore

private let exe = URL(fileURLWithPath: "/usr/bin/vphone-cli")

@MainActor
@Test func startInsertsAtFrontAndRuns() async {
    let runner = FakeStreamingRunner(lines: ["=== Export ===", "[+] done"], exitCode: 0)
    let center = TaskCenter(runner: runner)

    let first = center.start(title: "Export a", plannedStages: ["Export"], executable: exe, arguments: ["vm", "export", "a"])
    #expect(center.tasks.map(\.id) == [first.id])

    let second = center.start(title: "Export b", plannedStages: [], executable: exe, arguments: ["vm", "export", "b"])
    #expect(center.tasks.map(\.id) == [second.id, first.id])

    while first.status == .running || second.status == .running {
        await Task.yield()
    }
    #expect(first.status == .succeeded)
    #expect(second.status == .succeeded)
}
