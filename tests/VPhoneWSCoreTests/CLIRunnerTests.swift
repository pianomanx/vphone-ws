import Foundation
import Testing
@testable import VPhoneWSCore

@Test func fakeRunnerReturnsStubbedResultAndRecordsCall() async throws {
    let fake = FakeCLIRunner()
    fake.stub(arguments: ["vm", "list", "--json"],
              result: CLIResult(stdout: "[]", stderr: "", exitCode: 0))

    let out = try await fake.run(
        executable: URL(fileURLWithPath: "/usr/bin/vphone-cli"),
        arguments: ["vm", "list", "--json"], environment: nil)

    #expect(out.stdout == "[]")
    #expect(out.exitCode == 0)
    #expect(fake.calls.count == 1)
    #expect(fake.calls[0].arguments == ["vm", "list", "--json"])
}

@Test func systemRunnerCapturesStdoutAndExitCode() async throws {
    let runner = SystemCLIRunner()
    let out = try await runner.run(
        executable: URL(fileURLWithPath: "/bin/echo"),
        arguments: ["hello"], environment: nil)
    #expect(out.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
    #expect(out.exitCode == 0)
}

@Test(.timeLimit(.minutes(1)))
func systemRunnerDoesNotDeadlockOnLargeStdout() async throws {
    let runner = SystemCLIRunner()
    let out = try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "yes X | head -c 200000"], environment: nil)
    #expect(out.stdout.utf8.count == 200_000)
    #expect(out.exitCode == 0)
}

@Test(.timeLimit(.minutes(1)))
func systemRunnerDoesNotDeadlockOnLargeStderr() async throws {
    let runner = SystemCLIRunner()
    let out = try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "yes X | head -c 200000 1>&2"], environment: nil)
    #expect(out.stderr.utf8.count == 200_000)
    #expect(out.exitCode == 0)
}

@Test(.timeLimit(.minutes(1)))
func systemRunnerThrowsPromptlyForInvalidExecutable() async throws {
    let runner = SystemCLIRunner()
    await #expect(throws: (any Error).self) {
        _ = try await runner.run(
            executable: URL(fileURLWithPath: "/nonexistent/definitely-not-a-binary"),
            arguments: [], environment: nil)
    }
}

@Test(.timeLimit(.minutes(1)))
func systemRunnerSurvivesHighConcurrencyChurn() async throws {
    let runner = SystemCLIRunner()
    try await withThrowingTaskGroup(of: Int32.self) { group in
        for i in 0..<120 {
            group.addTask {
                try await runner.run(
                    executable: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "echo out-\(i); echo err-\(i) 1>&2"], environment: nil
                ).exitCode
            }
        }
        var count = 0
        for try await code in group {
            #expect(code == 0)
            count += 1
        }
        #expect(count == 120)
    }
}

@Test(.timeLimit(.minutes(1)))
func systemRunnerHandlesAbnormalTermination() async throws {
    let runner = SystemCLIRunner()
    let out = try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "echo partial; kill -9 $$"], environment: nil)
    #expect(out.stdout.contains("partial"))
    #expect(out.exitCode == 9)
}

@Test(.timeLimit(.minutes(1)))
func systemRunnerDoesNotLeakFileDescriptorsOnSuccess() async throws {
    let runner = SystemCLIRunner()
    let echo = URL(fileURLWithPath: "/bin/echo")

    func openFDCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0
    }

    _ = try await runner.run(executable: echo, arguments: ["warmup"], environment: nil)

    let before = openFDCount()
    for _ in 0..<200 {
        let out = try await runner.run(executable: echo, arguments: ["hi"], environment: nil)
        #expect(out.exitCode == 0)
    }
    let after = openFDCount()

    #expect(after - before < 20)
}
