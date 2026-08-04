# vphone-ws — Plan 1: Foundation & Library View

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the vphone-ws SwiftPM app and ship a read-only VM library — a sidebar of every VM with live running/stopped status and a detail Overview — by shelling out to `vphone-cli`.

**Architecture:** A testable core library (`VPhoneWSCore`: process layer, CLI client, models, running-state probe, store) plus a thin SwiftUI executable (`vphone-ws`) that binds views to the store. The app never links `vphone-cli` code; it treats `vphone-cli`'s `--json` output and exit codes as the contract. This mirrors the sibling `vphone-cli` repo's `VPhoneCore` (library) + `vphone-cli` (executable) split.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, swift-testing (`import Testing`). No third-party dependencies. macOS 15+.

## Global Constraints

- Platform: macOS 15+ (Sequoia); Apple Silicon. `Package.swift` pins `.macOS(.v15)`.
- Language: Swift 6, strict concurrency. `// MARK: -` sections; default (internal) access unless a type is part of the core's public API; minimal comments.
- Standalone: **no dependency on `vphone-cli` source** (`VPhoneCore`). Talk only to the CLI contract (`vm list --json`, `vm info --json`, exit codes).
- No third-party SwiftPM dependencies in v1.
- Test directory is lowercase `tests/` (never `Tests/` — silently ignored on the case-insensitive macOS FS).
- CLI invocation rules: always pass explicit VM **names**; pass `--json` for machine-readable output; never rely on the interactive picker (it throws off a TTY).
- The VM library root is `~/.vphone/VMs` (override `$VPHONE_LIBRARY_ROOT`); a directory is a VM iff it contains `config.plist`.
- Commit convention: `type(scope): imperative summary`, lower case, no trailing period (e.g. `feat(store): add lsof running-state probe`).
- `vm list --json` emits a JSON **array** of reports; `vm info <name> --json` emits one report **object**. Report keys (camelCase, from `VPhoneBundleReport`): `name`, `cpuCount`, `memoryMB`, `diskSizeBytes`, and optional `restoreInfo` = `{ "ios": {"version","build"}, "cloudOS": {"version","build"} }` (may be absent/null). Skipped-bundle warnings go to **stderr** — read JSON from stdout only.

---

### Task 1: Package scaffold & smoke test

**Files:**
- Create: `Package.swift`
- Create: `Sources/VPhoneWSCore/VPhoneWSCore.swift`
- Create: `Sources/vphone-ws/App.swift`
- Test: `tests/VPhoneWSCoreTests/SmokeTests.swift`

**Interfaces:**
- Produces: package targets `VPhoneWSCore` (library), `vphone-ws` (executable), `VPhoneWSCoreTests`; a `VPhoneWSCore.version` string symbol.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vphone-ws",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "VPhoneWSCore", path: "Sources/VPhoneWSCore"),
        .executableTarget(
            name: "vphone-ws",
            dependencies: ["VPhoneWSCore"],
            path: "Sources/vphone-ws"),
        .testTarget(
            name: "VPhoneWSCoreTests",
            dependencies: ["VPhoneWSCore"],
            path: "tests/VPhoneWSCoreTests"),
    ]
)
```

- [ ] **Step 2: Write the failing smoke test**

```swift
// tests/VPhoneWSCoreTests/SmokeTests.swift
import Testing
@testable import VPhoneWSCore

@Test func coreExposesVersion() {
    #expect(VPhoneWSCore.version == "0.1.0")
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `swift test --filter VPhoneWSCoreTests`
Expected: FAIL — `VPhoneWSCore` has no member `version` (compile error).

- [ ] **Step 4: Write the minimal core symbol and a placeholder App**

```swift
// Sources/VPhoneWSCore/VPhoneWSCore.swift
public enum VPhoneWSCore {
    public static let version = "0.1.0"
}
```

```swift
// Sources/vphone-ws/App.swift
import SwiftUI

@main
struct VPhoneWSApp: App {
    var body: some Scene {
        WindowGroup("vphone Workstation") {
            Text("vphone Workstation")
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
```

- [ ] **Step 5: Run build + test to verify green**

Run: `swift build && swift test --filter VPhoneWSCoreTests`
Expected: build succeeds; test PASSES.

- [ ] **Step 6: Verify the app window launches (manual)**

Run: `swift run vphone-ws`
Expected: a window titled "vphone Workstation" appears. Quit it (⌘Q).
Note: if `swift run` does not surface a window on this macOS build, add an `NSApplication`/`NSApplicationDelegate` entry point (as `vphone-cli`'s `main.swift` does) hosting the SwiftUI root via `NSHostingView`; the SwiftUI models below are unaffected.

- [ ] **Step 7: Add `.gitignore` and commit**

```bash
printf '.build/\n.swiftpm/\n*.xcodeproj\n' > .gitignore
git add Package.swift Sources tests .gitignore
git commit -m "feat(scaffold): SwiftPM package with core lib, app, and smoke test"
```

---

### Task 2: Process layer — `CLIRunner` protocol, real runner, and fake

**Files:**
- Create: `Sources/VPhoneWSCore/Process/CLIRunner.swift`
- Create: `Sources/VPhoneWSCore/Process/SystemCLIRunner.swift`
- Test: `tests/VPhoneWSCoreTests/CLIRunnerTests.swift`
- Test helper: `tests/VPhoneWSCoreTests/Support/FakeCLIRunner.swift`

**Interfaces:**
- Produces:
  - `struct CLIResult: Sendable { let stdout: String; let stderr: String; let exitCode: Int32 }`
  - `protocol CLIRunner: Sendable { func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> CLIResult }`
  - `struct SystemCLIRunner: CLIRunner` (real, over `Foundation.Process`)
  - `final class FakeCLIRunner: CLIRunner` (test double: canned results keyed by arguments; records calls)

- [ ] **Step 1: Write the failing test for the fake + protocol**

```swift
// tests/VPhoneWSCoreTests/CLIRunnerTests.swift
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
```

- [ ] **Step 2: Write the fake helper**

```swift
// tests/VPhoneWSCoreTests/Support/FakeCLIRunner.swift
import Foundation
@testable import VPhoneWSCore

final class FakeCLIRunner: CLIRunner, @unchecked Sendable {
    struct Call { let executable: URL; let arguments: [String]; let environment: [String: String]? }
    private(set) var calls: [Call] = []
    private var stubs: [[String]: CLIResult] = [:]

    func stub(arguments: [String], result: CLIResult) { stubs[arguments] = result }

    func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> CLIResult {
        calls.append(Call(executable: executable, arguments: arguments, environment: environment))
        guard let result = stubs[arguments] else {
            return CLIResult(stdout: "", stderr: "no stub for \(arguments)", exitCode: 127)
        }
        return result
    }
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `swift test --filter CLIRunnerTests`
Expected: FAIL — `CLIResult`/`CLIRunner`/`SystemCLIRunner` undefined.

- [ ] **Step 4: Implement the protocol and system runner**

```swift
// Sources/VPhoneWSCore/Process/CLIRunner.swift
import Foundation

public struct CLIResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public var succeeded: Bool { exitCode == 0 }
    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout; self.stderr = stderr; self.exitCode = exitCode
    }
}

public protocol CLIRunner: Sendable {
    func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> CLIResult
}
```

```swift
// Sources/VPhoneWSCore/Process/SystemCLIRunner.swift
import Foundation

public struct SystemCLIRunner: CLIRunner {
    public init() {}

    public func run(executable: URL, arguments: [String], environment: [String: String]?) async throws -> CLIResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let environment { process.environment = environment }
            let outPipe = Pipe(); let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: CLIResult(
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self),
                    exitCode: proc.terminationStatus))
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
```

- [ ] **Step 5: Run to verify green**

Run: `swift test --filter CLIRunnerTests`
Expected: both tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VPhoneWSCore/Process tests/VPhoneWSCoreTests
git commit -m "feat(process): add CLIRunner protocol, system runner, and test fake"
```

---

### Task 3: VM report models (Codable)

**Files:**
- Create: `Sources/VPhoneWSCore/Models/VMReport.swift`
- Test: `tests/VPhoneWSCoreTests/VMReportTests.swift`

**Interfaces:**
- Produces:
  - `struct OSVersion: Codable, Equatable, Sendable { let version: String; let build: String }`
  - `struct RestoreInfo: Codable, Equatable, Sendable { let ios: OSVersion; let cloudOS: OSVersion }`
  - `struct VMReport: Codable, Equatable, Sendable { let name: String; let cpuCount: Int; let memoryMB: Int; let diskSizeBytes: Int64; let restoreInfo: RestoreInfo? }`
  - Property names match the CLI's JSON keys exactly, so **no `CodingKeys` needed**.

- [ ] **Step 1: Write the failing test (array + null restoreInfo)**

```swift
// tests/VPhoneWSCoreTests/VMReportTests.swift
import Testing
import Foundation
@testable import VPhoneWSCore

@Test func decodesListWithAndWithoutRestoreInfo() throws {
    let json = """
    [
      {"name":"research-jb","cpuCount":8,"memoryMB":8192,"diskSizeBytes":68719476736,
       "restoreInfo":{"ios":{"version":"27.0","build":"24A5380h"},
                      "cloudOS":{"version":"26.4","build":"23E5207q"}}},
      {"name":"blank","cpuCount":8,"memoryMB":8192,"diskSizeBytes":68719476736}
    ]
    """
    let reports = try JSONDecoder().decode([VMReport].self, from: Data(json.utf8))
    #expect(reports.count == 2)
    #expect(reports[0].name == "research-jb")
    #expect(reports[0].restoreInfo?.ios.version == "27.0")
    #expect(reports[0].restoreInfo?.cloudOS.build == "23E5207q")
    #expect(reports[1].restoreInfo == nil)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter VMReportTests`
Expected: FAIL — `VMReport` undefined.

- [ ] **Step 3: Implement the models**

```swift
// Sources/VPhoneWSCore/Models/VMReport.swift
public struct OSVersion: Codable, Equatable, Sendable {
    public let version: String
    public let build: String
}

public struct RestoreInfo: Codable, Equatable, Sendable {
    public let ios: OSVersion
    public let cloudOS: OSVersion
}

public struct VMReport: Codable, Equatable, Sendable {
    public let name: String
    public let cpuCount: Int
    public let memoryMB: Int
    public let diskSizeBytes: Int64
    public let restoreInfo: RestoreInfo?
}
```

- [ ] **Step 4: Run to verify green**

Run: `swift test --filter VMReportTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VPhoneWSCore/Models tests/VPhoneWSCoreTests/VMReportTests.swift
git commit -m "feat(models): add VMReport/RestoreInfo codable models"
```

---

### Task 4: Locate the `vphone-cli` binary

**Files:**
- Create: `Sources/VPhoneWSCore/CLI/VPhoneCLILocator.swift`
- Test: `tests/VPhoneWSCoreTests/VPhoneCLILocatorTests.swift`

**Interfaces:**
- Produces:
  - `enum VPhoneCLILocation: Equatable, Sendable { case found(URL); case notFound }`
  - `struct VPhoneCLILocator { func locate(explicit: String?, pathLookup: (String) -> URL?) -> VPhoneCLILocation }`
  - Resolution order: `explicit` path (if it exists as passed) → `pathLookup("vphone-cli")` (injected `which`-style lookup) → `.notFound`.

- [ ] **Step 1: Write the failing test**

```swift
// tests/VPhoneWSCoreTests/VPhoneCLILocatorTests.swift
import Testing
import Foundation
@testable import VPhoneWSCore

@Test func prefersExplicitThenPathThenNotFound() {
    let loc = VPhoneCLILocator()
    let explicit = URL(fileURLWithPath: "/opt/custom/vphone-cli")

    // explicit wins when provided
    #expect(loc.locate(explicit: explicit.path, pathLookup: { _ in nil }) == .found(explicit))
    // falls back to PATH lookup
    let onPath = URL(fileURLWithPath: "/opt/homebrew/bin/vphone-cli")
    #expect(loc.locate(explicit: nil, pathLookup: { $0 == "vphone-cli" ? onPath : nil }) == .found(onPath))
    // nothing found
    #expect(loc.locate(explicit: nil, pathLookup: { _ in nil }) == .notFound)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter VPhoneCLILocatorTests`
Expected: FAIL — types undefined.

- [ ] **Step 3: Implement the locator**

```swift
// Sources/VPhoneWSCore/CLI/VPhoneCLILocator.swift
import Foundation

public enum VPhoneCLILocation: Equatable, Sendable {
    case found(URL)
    case notFound
}

public struct VPhoneCLILocator: Sendable {
    public init() {}

    /// `explicit`: a user-chosen path (Preferences). `pathLookup`: resolves a bare
    /// tool name on `$PATH` (inject `Self.whichLookup` in production).
    public func locate(explicit: String?, pathLookup: (String) -> URL?) -> VPhoneCLILocation {
        if let explicit, !explicit.isEmpty {
            return .found(URL(fileURLWithPath: explicit))
        }
        if let onPath = pathLookup("vphone-cli") {
            return .found(onPath)
        }
        return .notFound
    }

    /// Production `pathLookup`: run `/usr/bin/which <name>`.
    public static func whichLookup(_ name: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe(); process.standardOutput = pipe
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }
}
```

- [ ] **Step 4: Run to verify green**

Run: `swift test --filter VPhoneCLILocatorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VPhoneWSCore/CLI/VPhoneCLILocator.swift tests/VPhoneWSCoreTests/VPhoneCLILocatorTests.swift
git commit -m "feat(cli): add vphone-cli binary locator with injectable PATH lookup"
```

---

### Task 5: `VPhoneCLIClient` — `list` and `info`

**Files:**
- Create: `Sources/VPhoneWSCore/CLI/VPhoneCLIClient.swift`
- Test: `tests/VPhoneWSCoreTests/VPhoneCLIClientTests.swift`

**Interfaces:**
- Consumes: `CLIRunner`, `CLIResult` (Task 2); `VMReport` (Task 3).
- Produces:
  - `enum VPhoneCLIError: Error, Equatable { case nonZeroExit(code: Int32, stderr: String); case decodeFailed(String) }`
  - `struct VPhoneCLIClient { init(executable: URL, libraryRoot: String?, runner: CLIRunner) }`
  - `func listVMs() async throws -> [VMReport]` → argv `["vm","list","--json"]` (+ `["--library-root", root]` when set)
  - `func info(name: String) async throws -> VMReport` → argv `["vm","info", name, "--json"]` (+ library-root)
  - Both decode stdout; on non-zero exit throw `.nonZeroExit`.

- [ ] **Step 1: Write the failing test (argv assembly + decode + error)**

```swift
// tests/VPhoneWSCoreTests/VPhoneCLIClientTests.swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter VPhoneCLIClientTests`
Expected: FAIL — `VPhoneCLIClient`/`VPhoneCLIError` undefined.

- [ ] **Step 3: Implement the client**

```swift
// Sources/VPhoneWSCore/CLI/VPhoneCLIClient.swift
import Foundation

public enum VPhoneCLIError: Error, Equatable {
    case nonZeroExit(code: Int32, stderr: String)
    case decodeFailed(String)
}

public struct VPhoneCLIClient: Sendable {
    let executable: URL
    let libraryRoot: String?
    let runner: CLIRunner

    public init(executable: URL, libraryRoot: String?, runner: CLIRunner) {
        self.executable = executable
        self.libraryRoot = libraryRoot
        self.runner = runner
    }

    // MARK: - Read

    public func listVMs() async throws -> [VMReport] {
        let data = try await runJSON(["vm", "list", "--json"])
        return try decode([VMReport].self, from: data)
    }

    public func info(name: String) async throws -> VMReport {
        let data = try await runJSON(["vm", "info", name, "--json"])
        return try decode(VMReport.self, from: data)
    }

    // MARK: - Plumbing

    private func runJSON(_ base: [String]) async throws -> Data {
        var argv = base
        if let libraryRoot { argv += ["--library-root", libraryRoot] }
        let result = try await runner.run(executable: executable, arguments: argv, environment: nil)
        guard result.succeeded else {
            throw VPhoneCLIError.nonZeroExit(code: result.exitCode, stderr: result.stderr)
        }
        return Data(result.stdout.utf8)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw VPhoneCLIError.decodeFailed(String(describing: error)) }
    }
}
```

- [ ] **Step 4: Run to verify green**

Run: `swift test --filter VPhoneCLIClientTests`
Expected: all three PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VPhoneWSCore/CLI/VPhoneCLIClient.swift tests/VPhoneWSCoreTests/VPhoneCLIClientTests.swift
git commit -m "feat(cli): add VPhoneCLIClient list/info with json decode"
```

---

### Task 6: Running-state probe (`lsof`)

**Files:**
- Create: `Sources/VPhoneWSCore/State/RunningStateProbe.swift`
- Test: `tests/VPhoneWSCoreTests/RunningStateProbeTests.swift`

**Interfaces:**
- Consumes: `CLIRunner`, `CLIResult` (Task 2).
- Produces:
  - `static func parsePIDs(_ stdout: String) -> [Int32]` (one PID per line; ignores blanks/garbage)
  - `struct RunningStateProbe { init(runner: CLIRunner); func isRunning(diskImagePath: String) async throws -> Bool }`
  - argv: `["-t", "--", diskImagePath]` against `/usr/sbin/lsof`; running iff parsed PIDs non-empty. A non-zero exit from `lsof` (no holders) is treated as **not running**, not an error.

- [ ] **Step 1: Write the failing test**

```swift
// tests/VPhoneWSCoreTests/RunningStateProbeTests.swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter RunningStateProbeTests`
Expected: FAIL — `RunningStateProbe` undefined.

- [ ] **Step 3: Implement the probe**

```swift
// Sources/VPhoneWSCore/State/RunningStateProbe.swift
import Foundation

public struct RunningStateProbe: Sendable {
    static let lsof = URL(fileURLWithPath: "/usr/sbin/lsof")
    let runner: CLIRunner

    public init(runner: CLIRunner) { self.runner = runner }

    public static func parsePIDs(_ stdout: String) -> [Int32] {
        stdout.split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// A VM is running iff some process holds its Disk.img open. `lsof -t` exits
    /// non-zero when nothing matches — that means "not running", not an error.
    public func isRunning(diskImagePath: String) async throws -> Bool {
        let result = try await runner.run(
            executable: Self.lsof, arguments: ["-t", "--", diskImagePath], environment: nil)
        return !Self.parsePIDs(result.stdout).isEmpty
    }
}
```

- [ ] **Step 4: Run to verify green**

Run: `swift test --filter RunningStateProbeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VPhoneWSCore/State tests/VPhoneWSCoreTests/RunningStateProbeTests.swift
git commit -m "feat(state): add lsof-based running-state probe"
```

---

### Task 7: `VMStore` — observable library state

**Files:**
- Create: `Sources/VPhoneWSCore/Store/VMRow.swift`
- Create: `Sources/VPhoneWSCore/Store/VMStore.swift`
- Test: `tests/VPhoneWSCoreTests/VMStoreTests.swift`

**Interfaces:**
- Consumes: `VPhoneCLIClient` (Task 5), `RunningStateProbe` (Task 6), `VMReport` (Task 3).
- Produces:
  - `struct VMRow: Identifiable, Equatable, Sendable { let report: VMReport; var isRunning: Bool; var id: String { report.name } }` with display helpers `var displayVersions: String` (`"iOS 27.0 · cloudOS 26.4"` or `"—"`).
  - `@MainActor @Observable final class VMStore` with `init(client:probe:libraryRoot:)`, `var rows: [VMRow]`, `var loadError: String?`, and `func refresh() async`.
  - `refresh()` calls `client.listVMs()`, then for each report probes `isRunning(diskImagePath: libraryRoot + "/" + name + "/Disk.img")`, and publishes `rows`. On client error it sets `loadError` and leaves `rows` unchanged.

- [ ] **Step 1: Write the failing test for VMRow display**

```swift
// tests/VPhoneWSCoreTests/VMStoreTests.swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter VMStoreTests`
Expected: FAIL — `VMRow`/`VMStore` undefined.

- [ ] **Step 3: Implement `VMRow`**

```swift
// Sources/VPhoneWSCore/Store/VMRow.swift
public struct VMRow: Identifiable, Equatable, Sendable {
    public let report: VMReport
    public var isRunning: Bool
    public var id: String { report.name }

    public init(report: VMReport, isRunning: Bool) {
        self.report = report; self.isRunning = isRunning
    }

    public var displayVersions: String {
        guard let ri = report.restoreInfo else { return "—" }
        return "iOS \(ri.ios.version) · cloudOS \(ri.cloudOS.version)"
    }
}
```

- [ ] **Step 4: Implement `VMStore`**

```swift
// Sources/VPhoneWSCore/Store/VMStore.swift
import Foundation
import Observation

@MainActor
@Observable
public final class VMStore {
    public private(set) var rows: [VMRow] = []
    public private(set) var loadError: String?

    private let client: VPhoneCLIClient
    private let probe: RunningStateProbe
    private let libraryRoot: String

    public init(client: VPhoneCLIClient, probe: RunningStateProbe, libraryRoot: String) {
        self.client = client; self.probe = probe; self.libraryRoot = libraryRoot
    }

    public func refresh() async {
        do {
            let reports = try await client.listVMs()
            var next: [VMRow] = []
            for report in reports {
                let disk = "\(libraryRoot)/\(report.name)/Disk.img"
                let running = (try? await probe.isRunning(diskImagePath: disk)) ?? false
                next.append(VMRow(report: report, isRunning: running))
            }
            rows = next
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }
}
```

- [ ] **Step 5: Run to verify green**

Run: `swift test --filter VMStoreTests`
Expected: both PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VPhoneWSCore/Store tests/VPhoneWSCoreTests/VMStoreTests.swift
git commit -m "feat(store): add VMStore with running-state enrichment"
```

---

### Task 8: Library UI — sidebar list + detail Overview (read-only)

**Files:**
- Create: `Sources/VPhoneWSCore/Store/AppEnvironment.swift`
- Modify: `Sources/vphone-ws/App.swift`
- Create: `Sources/vphone-ws/Views/LibraryView.swift`
- Create: `Sources/vphone-ws/Views/VMDetailView.swift`

**Interfaces:**
- Consumes: `VMStore`, `VMRow`, `VPhoneCLIClient`, `VPhoneCLILocator`, `RunningStateProbe`, `SystemCLIRunner`.
- Produces: `@MainActor func makeVMStore() -> VMStore?` (wires the real runner/locator/library root; returns `nil` when `vphone-cli` isn't found so the UI can show a setup message).

This task is UI; verify by running the app against your real `~/.vphone/VMs`, not by unit test.

- [ ] **Step 1: Add the production wiring helper**

```swift
// Sources/VPhoneWSCore/Store/AppEnvironment.swift
import Foundation

public enum AppEnvironment {
    /// Default library root: $VPHONE_LIBRARY_ROOT or ~/.vphone/VMs.
    public static func defaultLibraryRoot() -> String {
        if let override = ProcessInfo.processInfo.environment["VPHONE_LIBRARY_ROOT"], !override.isEmpty {
            return override
        }
        return NSHomeDirectory() + "/.vphone/VMs"
    }

    /// Build a store against the real vphone-cli, or nil if the binary isn't found.
    @MainActor
    public static func makeVMStore(explicitCLIPath: String? = nil) -> VMStore? {
        let location = VPhoneCLILocator().locate(explicit: explicitCLIPath, pathLookup: VPhoneCLILocator.whichLookup)
        guard case .found(let exe) = location else { return nil }
        let runner = SystemCLIRunner()
        let root = defaultLibraryRoot()
        let client = VPhoneCLIClient(executable: exe, libraryRoot: root, runner: runner)
        return VMStore(client: client, probe: RunningStateProbe(runner: runner), libraryRoot: root)
    }
}
```

- [ ] **Step 2: Replace `App.swift` with a store-backed root**

```swift
// Sources/vphone-ws/App.swift
import SwiftUI
import VPhoneWSCore

@main
struct VPhoneWSApp: App {
    var body: some Scene {
        WindowGroup("vphone Workstation") {
            RootView()
                .frame(minWidth: 940, minHeight: 640)
        }
    }
}

struct RootView: View {
    @State private var store = AppEnvironment.makeVMStore()

    var body: some View {
        if let store {
            LibraryView(store: store)
        } else {
            ContentUnavailableView(
                "vphone-cli not found",
                systemImage: "terminal",
                description: Text("Install vphone-cli (e.g. `brew install zqxwce/tap/vphone-cli`) or set its path in Preferences."))
        }
    }
}
```

- [ ] **Step 3: Implement `LibraryView` (sidebar + selection)**

```swift
// Sources/vphone-ws/Views/LibraryView.swift
import SwiftUI
import VPhoneWSCore

struct LibraryView: View {
    @Bindable var store: VMStore
    @State private var selection: String?
    @State private var query = ""

    private var filtered: [VMRow] {
        query.isEmpty ? store.rows
            : store.rows.filter { $0.report.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationSplitView {
            List(filtered, selection: $selection) { row in
                HStack(spacing: 10) {
                    Circle()
                        .fill(row.isRunning ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.report.name).fontWeight(.medium)
                        Text(row.displayVersions)
                            .font(.caption).monospaced().foregroundStyle(.secondary)
                    }
                }
                .tag(row.report.name)
            }
            .searchable(text: $query, placement: .sidebar)
            .navigationTitle("VMs")
        } detail: {
            if let name = selection, let row = store.rows.first(where: { $0.report.name == name }) {
                VMDetailView(row: row)
            } else {
                Text("Select a VM").foregroundStyle(.secondary)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .overlay(alignment: .bottom) {
            if let err = store.loadError {
                Text(err).font(.caption).padding(6)
                    .background(.red.opacity(0.15)).clipShape(.rect(cornerRadius: 6)).padding()
            }
        }
    }
}
```

- [ ] **Step 4: Implement `VMDetailView` (Overview grid)**

```swift
// Sources/vphone-ws/Views/VMDetailView.swift
import SwiftUI
import VPhoneWSCore

struct VMDetailView: View {
    let row: VMRow

    private var specs: [(String, String)] {
        let r = row.report
        return [
            ("iOS", r.restoreInfo.map { "\($0.ios.version) (\($0.ios.build))" } ?? "—"),
            ("cloudOS", r.restoreInfo.map { "\($0.cloudOS.version) (\($0.cloudOS.build))" } ?? "—"),
            ("CPU", "\(r.cpuCount) cores"),
            ("Memory", "\(r.memoryMB) MB"),
            ("Disk", "\(r.diskSizeBytes / 1_073_741_824) GB"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Text(row.report.name).font(.largeTitle.bold())
                    Text(row.isRunning ? "Running" : "Stopped")
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(row.isRunning ? .green.opacity(0.18) : .secondary.opacity(0.15))
                        .clipShape(.capsule)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 1)], spacing: 1) {
                    ForEach(specs, id: \.0) { key, value in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key.uppercased()).font(.caption2).foregroundStyle(.secondary)
                            Text(value).fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.quaternary.opacity(0.4))
                    }
                }
                .clipShape(.rect(cornerRadius: 8))
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 5: Build and verify against real VMs (manual)**

Run: `swift build && swift run vphone-ws`
Expected: the window lists the VMs under `~/.vphone/VMs`, each with a green/gray status dot and `iOS … · cloudOS …` subtitle; selecting one shows the Overview with a Running/Stopped pill. Start a VM from the terminal (`vphone-cli vm launch <name>`) and confirm the dot turns green within a refresh (pull-to-refresh or relaunch).

- [ ] **Step 6: Commit**

```bash
git add Sources
git commit -m "feat(ui): read-only library view with sidebar status and detail overview"
```

---

### Task 9: `.app` bundle for a real windowed app

**Files:**
- Create: `Resources/Info.plist`
- Create: `scripts/bundle.sh`

**Interfaces:**
- Produces: `scripts/bundle.sh` building `.build/vphone-ws.app` from the release binary. No entitlements or signing needed (the app holds none; it only spawns `vphone-cli`).

- [ ] **Step 1: Write `Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>vphone Workstation</string>
    <key>CFBundleIdentifier</key><string>com.vphone.ws</string>
    <key>CFBundleExecutable</key><string>vphone-ws</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

- [ ] **Step 2: Write `scripts/bundle.sh`**

```bash
#!/bin/zsh
set -euo pipefail
cd "${0:a:h}/.."
swift build -c release
APP=".build/vphone-ws.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp .build/release/vphone-ws "$APP/Contents/MacOS/vphone-ws"
echo "built $APP"
```

- [ ] **Step 3: Build the bundle and launch it (manual)**

Run: `chmod +x scripts/bundle.sh && ./scripts/bundle.sh && open .build/vphone-ws.app`
Expected: the app opens as a normal Dock app (icon, menu bar) and shows the library.

- [ ] **Step 4: Commit**

```bash
git add Resources scripts/bundle.sh
git commit -m "build: add .app bundling script and Info.plist"
```

---

## Self-Review

**Spec coverage (Plan 1 slice of the design spec §3–§6.1):**
- Service layer `VPhoneCLIClient` → Tasks 4–5. `VMStore` → Task 7. Process abstraction (extensibility seam) → Task 2. ✓
- Binary discovery, invoke-in-place, explicit-name rule → Tasks 4–5, 8. ✓
- Data model: `restoreInfo` iOS+cloudOS from JSON, no plist parsing → Tasks 3, 5. ✓
- Running state via `lsof` on `Disk.img` → Task 6, wired in Task 7. ✓
- Main window: sidebar (name, status dot, `iOS · cloudOS` subtitle, search), detail Overview → Task 8. ✓
- Deferred to later plans (correctly out of Plan 1): Start/Stop/Show-screen & LaunchCoordinator, Settings, clone/rename/delete/export/import, create wizard, task console, host readiness, variant sidecar. Tracked in Plans 2–3.

**Placeholder scan:** none — every step has runnable code/commands.

**Type consistency:** `CLIRunner.run(executable:arguments:environment:)` used identically in Tasks 2/5/6/7; `CLIResult(stdout:stderr:exitCode:)` consistent; `VMReport`/`RestoreInfo`/`OSVersion` field names match the CLI JSON keys and are reused unchanged in Tasks 5/7/8; `VMStore(client:probe:libraryRoot:)` and `VMRow(report:isRunning:)` signatures match between definition (Task 7) and use (Task 8). ✓

**Note on `--library-root`:** the client always appends `--library-root <root>` when set; the store computes `Disk.img` paths from that same root, so list output and probe target stay consistent even under `$VPHONE_LIBRARY_ROOT`.
