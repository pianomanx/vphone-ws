# vphone-ws — Plan 2: Lifecycle & Management

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the library actionable — start/stop a VM (handing the display to `vphone-cli`), edit its settings, clone/rename/delete it, and check host readiness — building on Plan 1's foundation.

**Architecture:** A `ProcessLauncher` spawns the long-running `vphone-cli vm launch` as a tracked detached child (distinct from Plan 1's capture-to-completion `CLIRunner`). A `LaunchCoordinator` owns launch/stop/show-screen. `VPhoneCLIClient` gains the fast management verbs (config/clone/rename/delete). `HostReadiness` runs prerequisite checks. SwiftUI gains actions, a Settings sheet, and a readiness panel.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, swift-testing. No third-party dependencies. macOS 15+.

## Global Constraints

- All constraints from Plan 1 apply verbatim (macOS 15+, Swift 6 strict concurrency, no `vphone-cli` source dependency, lowercase `tests/`, explicit VM names, commit convention).
- Non-interactive CLI rules that this plan depends on: `vm delete` **must** pass `--force`; `vm rename` and `vm clone` **must** pass both names; `vm config` accepts `--cpu`, `--memory`, and (once the CLI supports it) `--network`.
- `vm config --network` persists the mode but has **no runtime effect** until the VZ backend honors it (main still hardcodes NAT) — the Settings UI must not imply an immediate boot change.
- Running/stopped truth is always the `lsof` probe from Plan 1 — never assume a spawned launch succeeded; let the next `VMStore.refresh()` confirm.

## File Structure

- `Sources/VPhoneWSCore/Process/ProcessLauncher.swift` — detached spawn protocol + system impl.
- `Sources/VPhoneWSCore/Lifecycle/LaunchCoordinator.swift` — launch/stop/show-screen.
- `Sources/VPhoneWSCore/CLI/VPhoneCLIClient+Manage.swift` — config/clone/rename/delete verbs.
- `Sources/VPhoneWSCore/Host/HostCheck.swift` + `HostReadiness.swift` — readiness model + checks.
- `Sources/vphone-ws/Views/VMDetailView.swift` (modify) — Start/Stop/Show/Settings actions.
- `Sources/vphone-ws/Views/SettingsSheet.swift`, `HostReadinessSheet.swift` — new sheets.

---

### Task 1: `ProcessLauncher` — detached child spawn

**Files:**
- Create: `Sources/VPhoneWSCore/Process/ProcessLauncher.swift`
- Test: `tests/VPhoneWSCoreTests/ProcessLauncherTests.swift`
- Test helper: `tests/VPhoneWSCoreTests/Support/FakeProcessLauncher.swift`

**Interfaces:**
- Produces:
  - `struct LaunchedProcess: Sendable { let pid: Int32 }`
  - `protocol ProcessLauncher: Sendable { func launch(executable: URL, arguments: [String], environment: [String: String]?) throws -> LaunchedProcess }`
  - `struct SystemProcessLauncher: ProcessLauncher` — spawns via `Foundation.Process`, returns immediately (does **not** wait), returns the child pid.
  - `final class FakeProcessLauncher: ProcessLauncher` — records calls, returns a stub pid.

- [ ] **Step 1: Write the failing test**

```swift
// tests/VPhoneWSCoreTests/ProcessLauncherTests.swift
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
    // `/bin/sleep 5` returns a live pid immediately; we don't wait for it.
    let p = try launcher.launch(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], environment: nil)
    #expect(p.pid > 0)
    kill(p.pid, SIGTERM)  // clean up
}
```

- [ ] **Step 2: Write the fake helper**

```swift
// tests/VPhoneWSCoreTests/Support/FakeProcessLauncher.swift
import Foundation
@testable import VPhoneWSCore

final class FakeProcessLauncher: ProcessLauncher, @unchecked Sendable {
    struct Call { let executable: URL; let arguments: [String]; let environment: [String: String]? }
    private(set) var calls: [Call] = []
    let stubPID: Int32
    init(stubPID: Int32 = 1) { self.stubPID = stubPID }

    func launch(executable: URL, arguments: [String], environment: [String: String]?) throws -> LaunchedProcess {
        calls.append(Call(executable: executable, arguments: arguments, environment: environment))
        return LaunchedProcess(pid: stubPID)
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --filter ProcessLauncherTests`
Expected: FAIL — types undefined.

- [ ] **Step 4: Implement**

```swift
// Sources/VPhoneWSCore/Process/ProcessLauncher.swift
import Foundation

public struct LaunchedProcess: Sendable { public let pid: Int32 }

public protocol ProcessLauncher: Sendable {
    func launch(executable: URL, arguments: [String], environment: [String: String]?) throws -> LaunchedProcess
}

public struct SystemProcessLauncher: ProcessLauncher {
    public init() {}
    public func launch(executable: URL, arguments: [String], environment: [String: String]?) throws -> LaunchedProcess {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        try process.run()               // returns immediately; we do not waitUntilExit
        return LaunchedProcess(pid: process.processIdentifier)
    }
}
```

- [ ] **Step 5: Run to verify green**

Run: `swift test --filter ProcessLauncherTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VPhoneWSCore/Process/ProcessLauncher.swift tests/VPhoneWSCoreTests/ProcessLauncherTests.swift tests/VPhoneWSCoreTests/Support/FakeProcessLauncher.swift
git commit -m "feat(process): add detached ProcessLauncher and fake"
```

---

### Task 2: `LaunchCoordinator` — launch / stop / show-screen

**Files:**
- Create: `Sources/VPhoneWSCore/Lifecycle/LaunchCoordinator.swift`
- Test: `tests/VPhoneWSCoreTests/LaunchCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ProcessLauncher` (Task 1), `VPhoneCLIClient` (Plan 1).
- Produces:
  - `@MainActor final class LaunchCoordinator` with `init(executable: URL, libraryRoot: String?, launcher: ProcessLauncher, client: VPhoneCLIClient)`.
  - `func launch(name: String) throws` → spawns `vphone-cli vm launch <name>` (+ `--library-root` when set); records pid in `runningPIDs[name]`.
  - `func stop(name: String) async throws` → runs `vphone-cli vm stop <name>` via the client's runner; clears `runningPIDs[name]`.
  - `func showScreen(name: String)` → best-effort raise: `NSRunningApplication(processIdentifier:)?.activate()` for the recorded pid.
  - `var runningPIDs: [String: Int32]` (for show-screen + tests).

- [ ] **Step 1: Write the failing test (argv assembly for launch & stop)**

```swift
// tests/VPhoneWSCoreTests/LaunchCoordinatorTests.swift
import Testing
import Foundation
@testable import VPhoneWSCore

private let exe = URL(fileURLWithPath: "/usr/bin/vphone-cli")

@MainActor
@Test func launchSpawnsWithExplicitNameAndLibraryRoot() throws {
    let launcher = FakeProcessLauncher(stubPID: 77)
    let client = VPhoneCLIClient(executable: exe, libraryRoot: "/lib", runner: FakeCLIRunner())
    let coord = LaunchCoordinator(executable: exe, libraryRoot: "/lib", launcher: launcher, client: client)
    try coord.launch(name: "a")
    #expect(launcher.calls[0].arguments == ["vm", "launch", "a", "--library-root", "/lib"])
    #expect(coord.runningPIDs["a"] == 77)
}

@MainActor
@Test func stopRunsVmStopAndClearsPID() async throws {
    let runner = FakeCLIRunner()
    runner.stub(arguments: ["vm", "stop", "a", "--library-root", "/lib"],
                result: CLIResult(stdout: "a: stopped", stderr: "", exitCode: 0))
    let client = VPhoneCLIClient(executable: exe, libraryRoot: "/lib", runner: runner)
    let coord = LaunchCoordinator(executable: exe, libraryRoot: "/lib", launcher: FakeProcessLauncher(), client: client)
    coord.runningPIDs["a"] = 5
    try await coord.stop(name: "a")
    #expect(runner.calls.contains { $0.arguments == ["vm", "stop", "a", "--library-root", "/lib"] })
    #expect(coord.runningPIDs["a"] == nil)
}
```

- [ ] **Step 2: Add a `stop` verb to the client** (needed by the coordinator)

Add to `Sources/VPhoneWSCore/CLI/VPhoneCLIClient.swift`:

```swift
    /// `vm stop <name>` — quick, returns human text; we only care about exit status.
    public func stop(name: String) async throws {
        _ = try await runText(["vm", "stop", name])
    }

    /// Run a subcommand that prints human text (not JSON); throw on non-zero exit.
    @discardableResult
    func runText(_ base: [String]) async throws -> String {
        var argv = base
        if let libraryRoot { argv += ["--library-root", libraryRoot] }
        let result = try await runner.run(executable: executable, arguments: argv, environment: nil)
        guard result.succeeded else { throw VPhoneCLIError.nonZeroExit(code: result.exitCode, stderr: result.stderr) }
        return result.stdout
    }
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --filter LaunchCoordinatorTests`
Expected: FAIL — `LaunchCoordinator` undefined.

- [ ] **Step 4: Implement the coordinator**

```swift
// Sources/VPhoneWSCore/Lifecycle/LaunchCoordinator.swift
import Foundation
import AppKit

@MainActor
public final class LaunchCoordinator {
    public private(set) var runningPIDs: [String: Int32] = [:]

    private let executable: URL
    private let libraryRoot: String?
    private let launcher: ProcessLauncher
    private let client: VPhoneCLIClient

    public init(executable: URL, libraryRoot: String?, launcher: ProcessLauncher, client: VPhoneCLIClient) {
        self.executable = executable; self.libraryRoot = libraryRoot
        self.launcher = launcher; self.client = client
    }

    public func launch(name: String) throws {
        var argv = ["vm", "launch", name]
        if let libraryRoot { argv += ["--library-root", libraryRoot] }
        let p = try launcher.launch(executable: executable, arguments: argv, environment: nil)
        runningPIDs[name] = p.pid
    }

    public func stop(name: String) async throws {
        try await client.stop(name: name)
        runningPIDs[name] = nil
    }

    /// Best-effort: bring the vphone-cli VM window forward.
    public func showScreen(name: String) {
        guard let pid = runningPIDs[name],
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate(options: [.activateAllWindows])
    }
}
```

- [ ] **Step 5: Run to verify green**

Run: `swift test --filter LaunchCoordinatorTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VPhoneWSCore/Lifecycle Sources/VPhoneWSCore/CLI/VPhoneCLIClient.swift tests/VPhoneWSCoreTests/LaunchCoordinatorTests.swift
git commit -m "feat(lifecycle): add LaunchCoordinator for launch/stop/show-screen"
```

---

### Task 3: Management verbs — config / clone / rename / delete

**Files:**
- Create: `Sources/VPhoneWSCore/CLI/VPhoneCLIClient+Manage.swift`
- Test: `tests/VPhoneWSCoreTests/VPhoneCLIClientManageTests.swift`

**Interfaces:**
- Consumes: `VPhoneCLIClient` (Plan 1).
- Produces (extension methods on `VPhoneCLIClient`):
  - `func setConfig(name: String, cpu: Int?, memoryMB: Int?, network: String?) async throws` → `vm config <name>` + `--cpu`/`--memory`/`--network` for each non-nil.
  - `func clone(name: String, to newName: String) async throws` → `vm clone <name> <newName>`.
  - `func rename(name: String, to newName: String) async throws` → `vm rename <name> <newName>`.
  - `func delete(name: String) async throws` → `vm delete <name> --force`.

- [ ] **Step 1: Write the failing tests (argv assembly)**

```swift
// tests/VPhoneWSCoreTests/VPhoneCLIClientManageTests.swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter VPhoneCLIClientManageTests`
Expected: FAIL — methods undefined.

- [ ] **Step 3: Implement the extension**

```swift
// Sources/VPhoneWSCore/CLI/VPhoneCLIClient+Manage.swift
import Foundation

extension VPhoneCLIClient {
    public func setConfig(name: String, cpu: Int?, memoryMB: Int?, network: String?) async throws {
        var argv = ["vm", "config", name]
        if let cpu { argv += ["--cpu", String(cpu)] }
        if let memoryMB { argv += ["--memory", String(memoryMB)] }
        if let network { argv += ["--network", network] }
        _ = try await runText(argv)
    }

    public func clone(name: String, to newName: String) async throws {
        _ = try await runText(["vm", "clone", name, newName])
    }

    public func rename(name: String, to newName: String) async throws {
        _ = try await runText(["vm", "rename", name, newName])
    }

    public func delete(name: String) async throws {
        _ = try await runText(["vm", "delete", name, "--force"])
    }
}
```

Note: `runText` was made accessible in Plan 2 Task 2; if it is still `private`, relax it to internal (`func runText`) so this extension in the same module can call it.

- [ ] **Step 4: Run to verify green**

Run: `swift test --filter VPhoneCLIClientManageTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VPhoneWSCore/CLI/VPhoneCLIClient+Manage.swift tests/VPhoneWSCoreTests/VPhoneCLIClientManageTests.swift
git commit -m "feat(cli): add config/clone/rename/delete management verbs"
```

---

### Task 4: Host readiness checks

**Files:**
- Create: `Sources/VPhoneWSCore/Host/HostCheck.swift`
- Create: `Sources/VPhoneWSCore/Host/HostReadiness.swift`
- Test: `tests/VPhoneWSCoreTests/HostReadinessTests.swift`

**Interfaces:**
- Consumes: `CLIRunner` (Plan 1), `VPhoneCLILocator` (Plan 1).
- Produces:
  - `enum CheckStatus: Equatable, Sendable { case ok; case attention }`
  - `struct HostCheck: Identifiable, Equatable, Sendable { let id: String; let title: String; let status: CheckStatus; let detail: String; let fixCommand: String? }`
  - Pure evaluators (each takes raw command output, returns a `HostCheck`) — the testable core:
    - `static func evalNestedVM(hvVmmPresent stdout: String) -> HostCheck` — `kern.hv_vmm_present` sysctl value; `0` ⇒ ok, else attention.
    - `static func evalMacOS(version: OperatingSystemVersion) -> HostCheck` — major ≥ 15 ⇒ ok.
    - `static func evalAMFIDont(pgrepOutput stdout: String) -> HostCheck` — non-empty pid list ⇒ ok, else attention with the start command.
    - `static func evalCLI(_ location: VPhoneCLILocation) -> HostCheck`.
  - `struct HostReadiness { init(runner: CLIRunner); func runAll() async -> [HostCheck] }` (wires the evaluators to real `sysctl`/`pgrep`/version calls).

- [ ] **Step 1: Write the failing tests for the pure evaluators**

```swift
// tests/VPhoneWSCoreTests/HostReadinessTests.swift
import Testing
import Foundation
@testable import VPhoneWSCore

@Test func nestedVMEvaluator() {
    #expect(HostReadiness.evalNestedVM(hvVmmPresent: "0\n").status == .ok)
    #expect(HostReadiness.evalNestedVM(hvVmmPresent: "1\n").status == .attention)
}

@Test func macOSEvaluator() {
    #expect(HostReadiness.evalMacOS(version: .init(majorVersion: 15, minorVersion: 2, patchVersion: 0)).status == .ok)
    #expect(HostReadiness.evalMacOS(version: .init(majorVersion: 14, minorVersion: 6, patchVersion: 0)).status == .attention)
}

@Test func amfidontEvaluator() {
    #expect(HostReadiness.evalAMFIDont(pgrepOutput: "532\n").status == .ok)
    let miss = HostReadiness.evalAMFIDont(pgrepOutput: "")
    #expect(miss.status == .attention)
    #expect(miss.fixCommand != nil)
}

@Test func cliEvaluator() {
    #expect(HostReadiness.evalCLI(.found(URL(fileURLWithPath: "/opt/homebrew/bin/vphone-cli"))).status == .ok)
    #expect(HostReadiness.evalCLI(.notFound).status == .attention)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter HostReadinessTests`
Expected: FAIL — types undefined.

- [ ] **Step 3: Implement the check model + evaluators**

```swift
// Sources/VPhoneWSCore/Host/HostCheck.swift
public enum CheckStatus: Equatable, Sendable { case ok, attention }

public struct HostCheck: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let status: CheckStatus
    public let detail: String
    public let fixCommand: String?
    public init(id: String, title: String, status: CheckStatus, detail: String, fixCommand: String? = nil) {
        self.id = id; self.title = title; self.status = status; self.detail = detail; self.fixCommand = fixCommand
    }
}
```

```swift
// Sources/VPhoneWSCore/Host/HostReadiness.swift
import Foundation

public struct HostReadiness: Sendable {
    let runner: CLIRunner
    public init(runner: CLIRunner) { self.runner = runner }

    // MARK: - Pure evaluators

    public static func evalNestedVM(hvVmmPresent stdout: String) -> HostCheck {
        let nested = stdout.trimmingCharacters(in: .whitespacesAndNewlines) != "0"
        return HostCheck(id: "nested", title: "Not running inside a VM",
            status: nested ? .attention : .ok,
            detail: nested ? "kern.hv_vmm_present = 1 — nested PV=3 guests can't boot."
                           : "kern.hv_vmm_present = 0 — good.")
    }

    public static func evalMacOS(version: OperatingSystemVersion) -> HostCheck {
        let ok = version.majorVersion >= 15
        return HostCheck(id: "macos", title: "macOS 15 or newer",
            status: ok ? .ok : .attention,
            detail: "macOS \(version.majorVersion).\(version.minorVersion)")
    }

    public static func evalAMFIDont(pgrepOutput stdout: String) -> HostCheck {
        let running = !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HostCheck(id: "amfidont", title: "AMFI allowlist (amfidont) is running",
            status: running ? .ok : .attention,
            detail: running ? "amfidont is active." :
                "Not running — the signed VM binary is killed on launch without it. It must stay running.",
            fixCommand: running ? nil : "vphone-amfidont")
    }

    public static func evalCLI(_ location: VPhoneCLILocation) -> HostCheck {
        if case .found(let url) = location {
            return HostCheck(id: "cli", title: "vphone-cli found", status: .ok, detail: url.path)
        }
        return HostCheck(id: "cli", title: "vphone-cli found", status: .attention,
            detail: "Not on PATH.", fixCommand: "brew install zqxwce/tap/vphone-cli")
    }

    // MARK: - Live runner

    public func runAll() async -> [HostCheck] {
        async let hv = sysctl("kern.hv_vmm_present")
        async let amfi = pgrep("amfidont")
        let cliLoc = VPhoneCLILocator().locate(explicit: nil, pathLookup: VPhoneCLILocator.whichLookup)
        return [
            Self.evalCLI(cliLoc),
            Self.evalMacOS(version: ProcessInfo.processInfo.operatingSystemVersion),
            Self.evalNestedVM(hvVmmPresent: await hv),
            Self.evalAMFIDont(pgrepOutput: await amfi),
        ]
    }

    private func sysctl(_ key: String) async -> String {
        (try? await runner.run(executable: URL(fileURLWithPath: "/usr/sbin/sysctl"),
                               arguments: ["-n", key], environment: nil))?.stdout ?? ""
    }

    private func pgrep(_ name: String) async -> String {
        (try? await runner.run(executable: URL(fileURLWithPath: "/usr/bin/pgrep"),
                               arguments: ["-x", name], environment: nil))?.stdout ?? ""
    }
}
```

- [ ] **Step 4: Run to verify green**

Run: `swift test --filter HostReadinessTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VPhoneWSCore/Host tests/VPhoneWSCoreTests/HostReadinessTests.swift
git commit -m "feat(host): add host-readiness checks with pure evaluators"
```

---

### Task 5: Wire actions into the app (Start/Stop/Show/Settings/Clone/Rename/Delete + Readiness)

**Files:**
- Modify: `Sources/VPhoneWSCore/Store/AppEnvironment.swift`
- Modify: `Sources/vphone-ws/Views/VMDetailView.swift`
- Create: `Sources/vphone-ws/Views/SettingsSheet.swift`
- Create: `Sources/vphone-ws/Views/HostReadinessSheet.swift`
- Modify: `Sources/vphone-ws/Views/LibraryView.swift`

This task is UI; verify by running the app. Actions call the store/coordinator/client built above.

- [ ] **Step 1: Extend `AppEnvironment` to also build a coordinator + readiness**

Add to `AppEnvironment` (return them alongside the store; expose the resolved `executable`, `libraryRoot`, and `runner` so the app can build a `LaunchCoordinator`, run `setConfig`, and run `HostReadiness`):

```swift
    public struct Services {
        public let store: VMStore
        public let coordinator: LaunchCoordinator
        public let client: VPhoneCLIClient
        public let readiness: HostReadiness
    }

    @MainActor
    public static func makeServices(explicitCLIPath: String? = nil) -> Services? {
        let location = VPhoneCLILocator().locate(explicit: explicitCLIPath, pathLookup: VPhoneCLILocator.whichLookup)
        guard case .found(let exe) = location else { return nil }
        let runner = SystemCLIRunner()
        let root = defaultLibraryRoot()
        let client = VPhoneCLIClient(executable: exe, libraryRoot: root, runner: runner)
        return Services(
            store: VMStore(client: client, probe: RunningStateProbe(runner: runner), libraryRoot: root),
            coordinator: LaunchCoordinator(executable: exe, libraryRoot: root,
                                           launcher: SystemProcessLauncher(), client: client),
            client: client,
            readiness: HostReadiness(runner: runner))
    }
```

Update `RootView` in `App.swift` to build `Services` once (`@State private var services = AppEnvironment.makeServices()`) and pass `services` into `LibraryView`.

- [ ] **Step 2: Add Start/Stop/Show + Settings/Clone/Delete to `VMDetailView`**

Give `VMDetailView` the `Services` and add a toolbar/header action row:

```swift
// action row (inside VMDetailView.body header HStack)
if row.isRunning {
    Button("Stop", role: .destructive) { Task { try? await services.coordinator.stop(name: row.report.name); await services.store.refresh() } }
    Button("Show screen") { services.coordinator.showScreen(name: row.report.name) }
} else {
    Button("Start") { try? services.coordinator.launch(name: row.report.name); Task { await services.store.refresh() } }
}
Button("Settings") { showSettings = true }
Menu("More") {
    Button("Clone…") { cloneTarget = row.report.name }
    Button("Delete…", role: .destructive) { confirmDelete = true }
}
```

Add `@State` flags (`showSettings`, `confirmDelete`, `cloneTarget`) and a `.confirmationDialog` for delete that calls `services.client.delete(name:)` then `store.refresh()`. Clone prompts for a new name (a small `.alert` with a `TextField`) then calls `services.client.clone(name:to:)`.

- [ ] **Step 3: Implement `SettingsSheet`**

```swift
// Sources/vphone-ws/Views/SettingsSheet.swift
import SwiftUI
import VPhoneWSCore

struct SettingsSheet: View {
    let row: VMRow
    let services: AppEnvironment.Services
    @Environment(\.dismiss) private var dismiss
    @State private var cpu: Double
    @State private var memory: Double
    @State private var network: String

    init(row: VMRow, services: AppEnvironment.Services) {
        self.row = row; self.services = services
        _cpu = State(initialValue: Double(row.report.cpuCount))
        _memory = State(initialValue: Double(row.report.memoryMB))
        _network = State(initialValue: "nat")
    }

    var body: some View {
        Form {
            Stepper("CPU cores: \(Int(cpu))", value: $cpu, in: 1...32)
            Stepper("Memory: \(Int(memory)) MB", value: $memory, in: 1024...65536, step: 1024)
            Picker("Network", selection: $network) {
                ForEach(["nat", "bridged", "hostOnly", "none"], id: \.self) { Text($0) }
            }
            Text("Applies on next boot; the VM must be stopped.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 380)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        try? await services.client.setConfig(
                            name: row.report.name, cpu: Int(cpu), memoryMB: Int(memory), network: network)
                        await services.store.refresh(); dismiss()
                    }
                }
                .disabled(row.isRunning)
            }
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }
}
```

- [ ] **Step 4: Implement `HostReadinessSheet` + toolbar pill**

```swift
// Sources/vphone-ws/Views/HostReadinessSheet.swift
import SwiftUI
import VPhoneWSCore

struct HostReadinessSheet: View {
    let readiness: HostReadiness
    @State private var checks: [HostCheck] = []

    var body: some View {
        List(checks) { check in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: check.status == .ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(check.status == .ok ? .green : .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(check.title).fontWeight(.semibold)
                    Text(check.detail).font(.callout).foregroundStyle(.secondary)
                    if let fix = check.fixCommand {
                        Text(fix).font(.caption).monospaced()
                            .textSelection(.enabled).padding(4)
                            .background(.quaternary).clipShape(.rect(cornerRadius: 4))
                    }
                }
            }.padding(.vertical, 4)
        }
        .frame(width: 520, height: 360)
        .task { checks = await readiness.runAll() }
    }
}
```

Add a toolbar item to `LibraryView` showing a pill ("Host ready" / "N need attention") that opens this sheet. Compute the summary by running `readiness.runAll()` on appear.

- [ ] **Step 5: Build and verify (manual)**

Run: `swift run vphone-ws`
Expected: selecting a stopped VM shows **Start**; clicking it launches vphone-cli's window and the dot goes green on refresh. **Stop** stops it. **Settings** opens the sheet (disabled Save while running); saving CPU/memory persists (confirm via `vphone-cli vm info <name>`). **Clone/Delete** work. The toolbar host pill opens the readiness sheet with live checks.

- [ ] **Step 6: Commit**

```bash
git add Sources
git commit -m "feat(ui): wire start/stop/show, settings, clone/delete, and host readiness"
```

---

## Self-Review

**Spec coverage (design spec §6.2, §6.5, §7 lifecycle/management):**
- Launch handoff (spawn `vm launch`, show-screen) + Stop → Tasks 1–2, 5. ✓
- Settings edits CPU/memory/network via `vm config`, disabled while running, "next boot" wording, no-runtime-effect caveat → Tasks 3, 5. ✓
- Clone/Rename/Delete with explicit names + `--force` → Tasks 3, 5. ✓
- Host readiness (nested VM, macOS, amfidont, cli-found) with fix commands → Tasks 4–5. ✓
- Running truth stays `lsof`-based (refresh after every action) → Task 5 wiring. ✓
- Deferred to Plan 3 (correct): create wizard, task console, export/import (long-running, share the streaming engine), variant sidecar.

**Placeholder scan:** none — every step has runnable code/commands.

**Type consistency:** `VPhoneCLIClient` extended consistently (`runText` relaxed to internal in Task 2, reused in Task 3); `LaunchCoordinator(executable:libraryRoot:launcher:client:)` matches definition/use; `AppEnvironment.Services` fields (`store/coordinator/client/readiness`) referenced identically in Task 5 views; `HostCheck`/`CheckStatus` consistent between Task 4 and the sheet in Task 5.

**Rename UI note:** `rename` verb exists (Task 3) but the Plan-2 UI exposes Clone/Delete/Settings in the More menu; wiring a Rename dialog is a trivial repeat of the Clone dialog and is included in Task 5 Step 2's More menu — add a `Button("Rename…")` mirroring Clone, calling `services.client.rename(name:to:)`.
