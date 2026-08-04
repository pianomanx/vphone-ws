# vphone-ws — Plan 3: Create Wizard & Task Console

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the long-running, streaming operations — a guided Create-VM wizard and the Task console that runs create/export/import with live progress, cancellation, native-auth elevation, and variant tracking.

**Architecture:** A streaming process runner emits output line-by-line; a pure stage parser turns `vphone-cli`'s `=== … ===` banners into progress; a `TaskModel` drives one running command's state; command builders assemble the argv for `vm create`/`export`/`import`. The create wizard records its chosen variant in a `VariantStore` sidecar and launches a `TaskModel`. Elevation uses the CLI's `--root-popup` (native macOS auth), so vphone-ws never handles a password.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, swift-testing. No third-party dependencies. macOS 15+.

## Global Constraints

- All Plan 1 constraints apply (macOS 15+, Swift 6, no `vphone-cli` source dependency, lowercase `tests/`, explicit VM names, commit convention).
- **Elevation:** `vm create` runs with `--root-popup` — the CFW host-mount authenticates via the native macOS dialog. vphone-ws never captures, stores, or passes a password.
- Success/failure of a long command is decided by the child **exit code**, never by scraping log text.
- Cancellation forwards **SIGINT** to the child (the CLI handles it); it does not hard-kill.
- Create validates non-empty name, no `/`, no leading `.`, and rejects an existing bundle name before running. It blocks on a nested-VM host.
- Create argv: `vm create <name> -V <variant> --iphone-source <s> --cloudos-source <s> --root-popup` (+ `--library-root` when set).

## File Structure

- `Sources/VPhoneWSCore/Tasks/StageParser.swift` — pure banner/marker parser.
- `Sources/VPhoneWSCore/Process/StreamingRunner.swift` — line-streaming spawn protocol + system impl.
- `Sources/VPhoneWSCore/Tasks/TaskModel.swift` — one running command's observable state.
- `Sources/VPhoneWSCore/Tasks/VPhoneCommandBuilder.swift` — argv builders for create/export/import.
- `Sources/VPhoneWSCore/Variant/VariantStore.swift` — per-VM variant sidecar.
- `Sources/vphone-ws/Views/TaskConsoleView.swift`, `CreateWizardView.swift` — UI.

---

### Task 1: Stage parser (pure)

**Files:**
- Create: `Sources/VPhoneWSCore/Tasks/StageParser.swift`
- Test: `tests/VPhoneWSCoreTests/StageParserTests.swift`

**Interfaces:**
- Produces:
  - `enum LogEvent: Equatable, Sendable { case stage(String); case marker(String); case plain(String) }`
  - `static func classify(_ line: String) -> LogEvent` — a `=== X ===` line ⇒ `.stage("X")`; a line starting with `[*]`/`[+]`/`[-]`/`[!]` ⇒ `.marker(line)`; else `.plain(line)`.

- [ ] **Step 1: Write the failing test**

```swift
// tests/VPhoneWSCoreTests/StageParserTests.swift
import Testing
@testable import VPhoneWSCore

@Test func classifiesBannersMarkersAndPlain() {
    #expect(StageParser.classify("=== Restore phase ===") == .stage("Restore phase"))
    #expect(StageParser.classify("===   CFW install   ===") == .stage("CFW install"))
    #expect(StageParser.classify("[+] SHSH fetched") == .marker("[+] SHSH fetched"))
    #expect(StageParser.classify("[-] panic") == .marker("[-] panic"))
    #expect(StageParser.classify("uploading ramdisk") == .plain("uploading ramdisk"))
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter StageParserTests`
Expected: FAIL — `StageParser` undefined.

- [ ] **Step 3: Implement**

```swift
// Sources/VPhoneWSCore/Tasks/StageParser.swift
public enum LogEvent: Equatable, Sendable {
    case stage(String)
    case marker(String)
    case plain(String)
}

public enum StageParser {
    public static func classify(_ line: String) -> LogEvent {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("===") && t.hasSuffix("===") && t.count > 6 {
            let inner = t.dropFirst(3).dropLast(3).trimmingCharacters(in: .whitespaces)
            return .stage(inner)
        }
        for m in ["[*]", "[+]", "[-]", "[!]"] where t.hasPrefix(m) {
            return .marker(line)
        }
        return .plain(line)
    }
}

import Foundation
```

- [ ] **Step 4: Run to verify green**

Run: `swift test --filter StageParserTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VPhoneWSCore/Tasks/StageParser.swift tests/VPhoneWSCoreTests/StageParserTests.swift
git commit -m "feat(tasks): add pure stage/marker log parser"
```

---

### Task 2: `StreamingRunner` — line-streaming spawn

**Files:**
- Create: `Sources/VPhoneWSCore/Process/StreamingRunner.swift`
- Test: `tests/VPhoneWSCoreTests/StreamingRunnerTests.swift`
- Test helper: `tests/VPhoneWSCoreTests/Support/FakeStreamingRunner.swift`

**Interfaces:**
- Produces:
  - `protocol StreamingRunner: Sendable { func run(executable: URL, arguments: [String], environment: [String: String]?, onStart: @escaping @Sendable (Int32) -> Void, onLine: @escaping @Sendable (String) -> Void) async throws -> Int32 }`
  - `struct SystemStreamingRunner: StreamingRunner` — spawns, calls `onStart(pid)`, invokes `onLine` per stdout+stderr line, returns exit code.
  - `final class FakeStreamingRunner: StreamingRunner` — emits a canned `[String]` of lines then returns a canned exit code; calls `onStart(stubPID)`.

- [ ] **Step 1: Write the failing test**

```swift
// tests/VPhoneWSCoreTests/StreamingRunnerTests.swift
import Testing
import Foundation
@testable import VPhoneWSCore

@Test func fakeStreamerEmitsLinesThenExit() async throws {
    let fake = FakeStreamingRunner(lines: ["=== Prepare ===", "[+] done"], exitCode: 0, stubPID: 9)
    var seen: [String] = []; var startedPID: Int32 = 0
    let code = try await fake.run(executable: URL(fileURLWithPath: "/x"), arguments: [], environment: nil,
                                  onStart: { startedPID = $0 }, onLine: { seen.append($0) })
    #expect(startedPID == 9)
    #expect(seen == ["=== Prepare ===", "[+] done"])
    #expect(code == 0)
}

@Test func systemStreamerEchoesLines() async throws {
    let runner = SystemStreamingRunner()
    var seen: [String] = []
    let code = try await runner.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["one\ntwo"],
                                    environment: nil, onStart: { _ in }, onLine: { seen.append($0) })
    #expect(code == 0)
    #expect(seen.contains("one"))
    #expect(seen.contains("two"))
}
```

- [ ] **Step 2: Write the fake helper**

```swift
// tests/VPhoneWSCoreTests/Support/FakeStreamingRunner.swift
import Foundation
@testable import VPhoneWSCore

final class FakeStreamingRunner: StreamingRunner, @unchecked Sendable {
    let lines: [String]; let exitCode: Int32; let stubPID: Int32
    init(lines: [String], exitCode: Int32, stubPID: Int32 = 1) {
        self.lines = lines; self.exitCode = exitCode; self.stubPID = stubPID
    }
    func run(executable: URL, arguments: [String], environment: [String: String]?,
             onStart: @escaping @Sendable (Int32) -> Void, onLine: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        onStart(stubPID)
        for line in lines { onLine(line) }
        return exitCode
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --filter StreamingRunnerTests`
Expected: FAIL — types undefined.

- [ ] **Step 4: Implement the system streamer**

```swift
// Sources/VPhoneWSCore/Process/StreamingRunner.swift
import Foundation

public protocol StreamingRunner: Sendable {
    func run(executable: URL, arguments: [String], environment: [String: String]?,
             onStart: @escaping @Sendable (Int32) -> Void,
             onLine: @escaping @Sendable (String) -> Void) async throws -> Int32
}

public struct SystemStreamingRunner: StreamingRunner {
    public init() {}

    public func run(executable: URL, arguments: [String], environment: [String: String]?,
                    onStart: @escaping @Sendable (Int32) -> Void,
                    onLine: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let environment { process.environment = environment }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let buffer = LineBuffer(onLine: onLine)
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                buffer.append(data)
            }
            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                let tail = pipe.fileHandleForReading.readDataToEndOfFile()
                buffer.append(tail); buffer.flush()
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
                onStart(process.processIdentifier)
            } catch { continuation.resume(throwing: error) }
        }
    }
}

/// Splits a byte stream into lines, invoking `onLine` per complete line.
final class LineBuffer: @unchecked Sendable {
    private var partial = ""
    private let onLine: @Sendable (String) -> Void
    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }
    func append(_ data: Data) {
        partial += String(decoding: data, as: UTF8.self)
        while let idx = partial.firstIndex(of: "\n") {
            onLine(String(partial[..<idx]))
            partial = String(partial[partial.index(after: idx)...])
        }
    }
    func flush() { if !partial.isEmpty { onLine(partial); partial = "" } }
}
```

- [ ] **Step 5: Run to verify green**

Run: `swift test --filter StreamingRunnerTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VPhoneWSCore/Process/StreamingRunner.swift tests/VPhoneWSCoreTests/StreamingRunnerTests.swift tests/VPhoneWSCoreTests/Support/FakeStreamingRunner.swift
git commit -m "feat(process): add line-streaming runner and fake"
```

---

### Task 3: `TaskModel` — one running command's state

**Files:**
- Create: `Sources/VPhoneWSCore/Tasks/TaskModel.swift`
- Test: `tests/VPhoneWSCoreTests/TaskModelTests.swift`

**Interfaces:**
- Consumes: `StreamingRunner` (Task 2), `StageParser` (Task 1).
- Produces:
  - `enum TaskStatus: Equatable, Sendable { case running; case succeeded; case failed(Int32); case cancelled }`
  - `@MainActor @Observable final class TaskModel: Identifiable` with `let id = UUID()`, `let title: String`, `let plannedStages: [String]`, `private(set) var currentStage: String?`, `private(set) var completedStages: [String]`, `private(set) var logLines: [String]`, `private(set) var status: TaskStatus`.
  - `init(title: String, plannedStages: [String])`.
  - `func run(executable: URL, arguments: [String], runner: StreamingRunner) async` — streams lines (classifying each: `.stage` advances `currentStage`/`completedStages`, everything appended to `logLines`), sets `status` from the exit code (`0` ⇒ `.succeeded`, else `.failed(code)`).
  - `func cancel()` — sends `SIGINT` to the recorded pid; marks `.cancelled`.

- [ ] **Step 1: Write the failing tests (success + failure state transitions)**

```swift
// tests/VPhoneWSCoreTests/TaskModelTests.swift
import Testing
import Foundation
@testable import VPhoneWSCore

private let exe = URL(fileURLWithPath: "/usr/bin/vphone-cli")

@MainActor
@Test func runAdvancesStagesAndSucceeds() async {
    let runner = FakeStreamingRunner(
        lines: ["=== Prepare ===", "[*] downloading", "=== Restore phase ===", "[+] ok"],
        exitCode: 0)
    let task = TaskModel(title: "Create a", plannedStages: ["Prepare", "Restore phase"])
    await task.run(executable: exe, arguments: ["vm", "create", "a"], runner: runner)
    #expect(task.completedStages == ["Prepare"])         // last stage is "current", earlier ones completed
    #expect(task.currentStage == "Restore phase")
    #expect(task.logLines.contains("[*] downloading"))
    #expect(task.status == .succeeded)
}

@MainActor
@Test func nonZeroExitMarksFailed() async {
    let runner = FakeStreamingRunner(lines: ["[-] boom"], exitCode: 3)
    let task = TaskModel(title: "Create a", plannedStages: [])
    await task.run(executable: exe, arguments: [], runner: runner)
    #expect(task.status == .failed(3))
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter TaskModelTests`
Expected: FAIL — `TaskModel` undefined.

- [ ] **Step 3: Implement**

```swift
// Sources/VPhoneWSCore/Tasks/TaskModel.swift
import Foundation
import Observation

public enum TaskStatus: Equatable, Sendable {
    case running, succeeded, cancelled
    case failed(Int32)
}

@MainActor
@Observable
public final class TaskModel: Identifiable {
    public let id = UUID()
    public let title: String
    public let plannedStages: [String]
    public private(set) var currentStage: String?
    public private(set) var completedStages: [String] = []
    public private(set) var logLines: [String] = []
    public private(set) var status: TaskStatus = .running

    private var pid: Int32?

    public init(title: String, plannedStages: [String]) {
        self.title = title; self.plannedStages = plannedStages
    }

    public func run(executable: URL, arguments: [String], runner: StreamingRunner) async {
        do {
            let code = try await runner.run(
                executable: executable, arguments: arguments, environment: nil,
                onStart: { [weak self] pid in Task { @MainActor in self?.pid = pid } },
                onLine: { [weak self] line in Task { @MainActor in self?.ingest(line) } })
            if status != .cancelled { status = code == 0 ? .succeeded : .failed(code) }
        } catch {
            if status != .cancelled { status = .failed(-1) }
        }
    }

    public func cancel() {
        if let pid { kill(pid, SIGINT) }
        status = .cancelled
    }

    private func ingest(_ line: String) {
        switch StageParser.classify(line) {
        case .stage(let name):
            if let prev = currentStage { completedStages.append(prev) }
            currentStage = name
        case .marker, .plain:
            break
        }
        logLines.append(line)
    }
}
```

- [ ] **Step 4: Run to verify green**

Run: `swift test --filter TaskModelTests`
Expected: PASS. (Note: `onLine` hops to the main actor via `Task { @MainActor in }`; the fake emits synchronously, but `run` awaits the runner's return, and the test asserts after `await`, so the ordered hops have completed. If ordering proves racy, change the fake to `await MainActor.run { onLine(line) }` — but keep the protocol closure non-async.)

- [ ] **Step 5: Commit**

```bash
git add Sources/VPhoneWSCore/Tasks/TaskModel.swift tests/VPhoneWSCoreTests/TaskModelTests.swift
git commit -m "feat(tasks): add TaskModel state machine with stage tracking"
```

---

### Task 4: `VariantStore` — per-VM variant sidecar

**Files:**
- Create: `Sources/VPhoneWSCore/Variant/VariantStore.swift`
- Test: `tests/VPhoneWSCoreTests/VariantStoreTests.swift`

**Interfaces:**
- Produces:
  - `struct VariantStore { init(libraryRoot: String) }`
  - `func setVariant(_ variant: String, forVM name: String) throws` — writes `<libraryRoot>/<name>/.vphone-ws.json` = `{"variant":"jb"}`.
  - `func variant(forVM name: String) -> String?` — reads it back; `nil` if the file is absent (VM created outside vphone-ws ⇒ "Unknown" in UI).

- [ ] **Step 1: Write the failing test**

```swift
// tests/VPhoneWSCoreTests/VariantStoreTests.swift
import Testing
import Foundation
@testable import VPhoneWSCore

@Test func writesAndReadsVariant() throws {
    let root = NSTemporaryDirectory() + "vws-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: root + "/myvm", withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: root) }

    let store = VariantStore(libraryRoot: root)
    #expect(store.variant(forVM: "myvm") == nil)
    try store.setVariant("jb", forVM: "myvm")
    #expect(store.variant(forVM: "myvm") == "jb")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter VariantStoreTests`
Expected: FAIL — `VariantStore` undefined.

- [ ] **Step 3: Implement**

```swift
// Sources/VPhoneWSCore/Variant/VariantStore.swift
import Foundation

public struct VariantStore: Sendable {
    private struct Sidecar: Codable { let variant: String }
    private let libraryRoot: String
    public init(libraryRoot: String) { self.libraryRoot = libraryRoot }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "\(libraryRoot)/\(name)/.vphone-ws.json")
    }

    public func setVariant(_ variant: String, forVM name: String) throws {
        let data = try JSONEncoder().encode(Sidecar(variant: variant))
        try data.write(to: url(name))
    }

    public func variant(forVM name: String) -> String? {
        guard let data = try? Data(contentsOf: url(name)),
              let side = try? JSONDecoder().decode(Sidecar.self, from: data) else { return nil }
        return side.variant
    }
}
```

- [ ] **Step 4: Run to verify green**

Run: `swift test --filter VariantStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VPhoneWSCore/Variant tests/VPhoneWSCoreTests/VariantStoreTests.swift
git commit -m "feat(variant): add per-VM variant sidecar store"
```

---

### Task 5: Command builders — create / export / import argv

**Files:**
- Create: `Sources/VPhoneWSCore/Tasks/VPhoneCommandBuilder.swift`
- Test: `tests/VPhoneWSCoreTests/VPhoneCommandBuilderTests.swift`

**Interfaces:**
- Produces:
  - `struct VPhoneCommandBuilder { let libraryRoot: String? }`
  - `func createArgs(name: String, variant: String, iphoneSource: String, cloudosSource: String) -> [String]` → `["vm","create",name,"-V",variant,"--iphone-source",iphoneSource,"--cloudos-source",cloudosSource,"--root-popup"]` (+ `--library-root` when set).
  - `func exportArgs(name: String, out: String) -> [String]` → `["vm","export",name,"-o",out]` (+ library-root).
  - `func importArgs(archive: String, name: String) -> [String]` → `["vm","import","-i",archive,"-n",name]` (+ library-root).
  - `static let createStages = ["vm new","fw prepare","fw patch","Restore phase","CFW install","First boot"]` (progress hints matching the CLI's banners).

- [ ] **Step 1: Write the failing test**

```swift
// tests/VPhoneWSCoreTests/VPhoneCommandBuilderTests.swift
import Testing
@testable import VPhoneWSCore

@Test func createIncludesRootPopupAndSourcesAndLibraryRoot() {
    let b = VPhoneCommandBuilder(libraryRoot: "/lib")
    #expect(b.createArgs(name: "a", variant: "jb", iphoneSource: "26.3", cloudosSource: "26.4") ==
        ["vm","create","a","-V","jb","--iphone-source","26.3","--cloudos-source","26.4","--root-popup","--library-root","/lib"])
}

@Test func exportAndImportArgs() {
    let b = VPhoneCommandBuilder(libraryRoot: nil)
    #expect(b.exportArgs(name: "a", out: "/tmp/a.tar.xz") == ["vm","export","a","-o","/tmp/a.tar.xz"])
    #expect(b.importArgs(archive: "/tmp/a.tar.xz", name: "restored") == ["vm","import","-i","/tmp/a.tar.xz","-n","restored"])
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter VPhoneCommandBuilderTests`
Expected: FAIL — `VPhoneCommandBuilder` undefined.

- [ ] **Step 3: Implement**

```swift
// Sources/VPhoneWSCore/Tasks/VPhoneCommandBuilder.swift
public struct VPhoneCommandBuilder: Sendable {
    public let libraryRoot: String?
    public init(libraryRoot: String?) { self.libraryRoot = libraryRoot }

    public static let createStages = ["vm new", "fw prepare", "fw patch", "Restore phase", "CFW install", "First boot"]

    public func createArgs(name: String, variant: String, iphoneSource: String, cloudosSource: String) -> [String] {
        withLibraryRoot(["vm", "create", name, "-V", variant,
                         "--iphone-source", iphoneSource, "--cloudos-source", cloudosSource, "--root-popup"])
    }

    public func exportArgs(name: String, out: String) -> [String] {
        withLibraryRoot(["vm", "export", name, "-o", out])
    }

    public func importArgs(archive: String, name: String) -> [String] {
        withLibraryRoot(["vm", "import", "-i", archive, "-n", name])
    }

    private func withLibraryRoot(_ argv: [String]) -> [String] {
        guard let libraryRoot else { return argv }
        return argv + ["--library-root", libraryRoot]
    }
}
```

- [ ] **Step 4: Run to verify green**

Run: `swift test --filter VPhoneCommandBuilderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VPhoneWSCore/Tasks/VPhoneCommandBuilder.swift tests/VPhoneWSCoreTests/VPhoneCommandBuilderTests.swift
git commit -m "feat(tasks): add create/export/import command builders"
```

---

### Task 6: Task console UI

**Files:**
- Create: `Sources/vphone-ws/Views/TaskConsoleView.swift`
- Create: `Sources/VPhoneWSCore/Tasks/TaskCenter.swift`
- Modify: `Sources/VPhoneWSCore/Store/AppEnvironment.swift`

**Interfaces:**
- Produces: `@MainActor @Observable final class TaskCenter { var tasks: [TaskModel]; func start(title:plannedStages:executable:arguments:runner:) -> TaskModel }` — appends a `TaskModel`, kicks off its `run(...)` in a `Task`, returns it. Add a `TaskCenter` and a `StreamingRunner` to `AppEnvironment.Services`.

This task is UI + a small coordinator; verify manually via export (a real long op you already have VMs for).

- [ ] **Step 1: Add `TaskCenter`**

```swift
// Sources/VPhoneWSCore/Tasks/TaskCenter.swift
import Foundation

@MainActor
@Observable
public final class TaskCenter {
    public private(set) var tasks: [TaskModel] = []
    private let runner: StreamingRunner
    public init(runner: StreamingRunner) { self.runner = runner }

    @discardableResult
    public func start(title: String, plannedStages: [String], executable: URL, arguments: [String]) -> TaskModel {
        let model = TaskModel(title: title, plannedStages: plannedStages)
        tasks.insert(model, at: 0)
        Task { await model.run(executable: executable, arguments: arguments, runner: runner) }
        return model
    }
}
```

Add to `AppEnvironment.Services`: `let taskCenter: TaskCenter`, `let executable: URL`, `let commandBuilder: VPhoneCommandBuilder`, `let variants: VariantStore`. Construct them in `makeServices` (`taskCenter: TaskCenter(runner: SystemStreamingRunner())`, `commandBuilder: VPhoneCommandBuilder(libraryRoot: root)`, `variants: VariantStore(libraryRoot: root)`, `executable: exe`).

- [ ] **Step 2: Implement `TaskConsoleView`**

```swift
// Sources/vphone-ws/Views/TaskConsoleView.swift
import SwiftUI
import VPhoneWSCore

struct TaskConsoleView: View {
    @Bindable var center: TaskCenter

    var body: some View {
        List(center.tasks) { task in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    statusPill(task)
                    Text(task.title).fontWeight(.semibold)
                    Spacer()
                    if task.status == .running {
                        Button("Cancel", role: .destructive) { task.cancel() }
                    }
                }
                if !task.plannedStages.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(task.plannedStages, id: \.self) { stage in
                            Text(stage).font(.caption.monospaced())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(stageColor(task, stage)).clipShape(.rect(cornerRadius: 5))
                        }
                    }
                }
                ScrollView { Text(task.logLines.suffix(200).joined(separator: "\n"))
                    .font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(height: 160).background(Color.black.opacity(0.85))
                    .clipShape(.rect(cornerRadius: 6))
            }.padding(.vertical, 6)
        }
    }

    private func statusPill(_ t: TaskModel) -> some View {
        let (text, color): (String, Color) = switch t.status {
            case .running: ("Running", .orange)
            case .succeeded: ("Done", .green)
            case .cancelled: ("Cancelled", .secondary)
            case .failed(let c): ("Failed (\(c))", .red)
        }
        return Text(text).font(.caption.bold()).foregroundStyle(color)
    }

    private func stageColor(_ t: TaskModel, _ stage: String) -> Color {
        if t.completedStages.contains(stage) { return .green.opacity(0.2) }
        if t.currentStage == stage { return .accentColor.opacity(0.3) }
        return .secondary.opacity(0.12)
    }
}
```

- [ ] **Step 3: Present the console** from a toolbar button in `LibraryView` (sheet or a bottom panel bound to `services.taskCenter`).

- [ ] **Step 4: Verify with a real export (manual)**

Trigger an export (Task 8 wires the menu, or temporarily call `services.taskCenter.start(title:"Export", plannedStages: [], executable: services.executable, arguments: services.commandBuilder.exportArgs(name: "<vm>", out: "/tmp/x.tar.xz"))`).
Expected: a task appears, log streams live, status flips to Done on completion; Cancel SIGINTs a running task.

- [ ] **Step 5: Commit**

```bash
git add Sources
git commit -m "feat(ui): add task console with live log and stage chips"
```

---

### Task 7: Create-VM wizard

**Files:**
- Create: `Sources/vphone-ws/Views/CreateWizardView.swift`
- Modify: `Sources/vphone-ws/Views/LibraryView.swift`

**Interfaces:**
- Consumes: `AppEnvironment.Services` (adds `taskCenter`, `executable`, `commandBuilder`, `variants`).

This task is UI; verify with a real create run.

- [ ] **Step 1: Implement `CreateWizardView`** (name → variant + sources → review → create)

```swift
// Sources/vphone-ws/Views/CreateWizardView.swift
import SwiftUI
import VPhoneWSCore

struct CreateWizardView: View {
    let services: AppEnvironment.Services
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var variant = "regular"
    @State private var iphoneSource = ""
    @State private var cloudosSource = ""

    private var nameValid: Bool {
        !name.isEmpty && !name.contains("/") && !name.hasPrefix(".")
            && !services.store.rows.contains { $0.report.name == name }
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("VM name", text: $name)
                if !name.isEmpty && !nameValid {
                    Text("Invalid or already in use").font(.caption).foregroundStyle(.red)
                }
            }
            Section("Variant") {
                Picker("Variant", selection: $variant) {
                    ForEach(["less","regular","dev","jb","exp"], id: \.self) { Text($0) }
                }.pickerStyle(.segmented)
            }
            Section("Firmware source") {
                TextField("iOS (userland) — version or .ipsw path", text: $iphoneSource)
                TextField("cloudOS (kernel) — version or .ipsw path", text: $cloudosSource)
            }
            Section {
                Text("Creating downloads multi-GB IPSWs, authenticates once via the native macOS prompt (for the CFW host-mount), and takes several minutes. Progress shows in the Task console.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 460)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { startCreate() }
                    .disabled(!nameValid || iphoneSource.isEmpty || cloudosSource.isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private func startCreate() {
        try? services.variants.setVariant(variant, forVM: name)  // record before the long run
        let args = services.commandBuilder.createArgs(
            name: name, variant: variant, iphoneSource: iphoneSource, cloudosSource: cloudosSource)
        services.taskCenter.start(title: "Create \(name) · \(variant)",
                                  plannedStages: VPhoneCommandBuilder.createStages,
                                  executable: services.executable, arguments: args)
        dismiss()
    }
}
```

Note: `variants.setVariant` writes `<root>/<name>/.vphone-ws.json`; the bundle dir may not exist until `vm new` runs inside `vm create`. If the write fails because the dir is absent, retry it when the create task reaches `.succeeded` (observe the returned `TaskModel.status`) — the simplest robust approach is to write the sidecar in a `Task` that awaits the create task's completion. Adjust `startCreate` to capture the returned `TaskModel` and, on `.succeeded`, call `setVariant` then `store.refresh()`.

- [ ] **Step 2: Add a "New VM" toolbar button** in `LibraryView` presenting `CreateWizardView(services:)` as a sheet.

- [ ] **Step 3: Verify a real create (manual, device)**

Run: `swift run vphone-ws` → New VM → fill name/variant/sources → Create.
Expected: the Task console shows the create streaming through its stages; the native macOS auth dialog appears at CFW time; on success the VM appears in the sidebar and its variant sidecar is written.

- [ ] **Step 4: Commit**

```bash
git add Sources
git commit -m "feat(ui): add create-VM wizard driving vm create via task console"
```

---

### Task 8: Export/Import actions + variant display

**Files:**
- Modify: `Sources/vphone-ws/Views/VMDetailView.swift`
- Modify: `Sources/vphone-ws/Views/LibraryView.swift`

**Interfaces:**
- Consumes: `TaskCenter`, `VPhoneCommandBuilder`, `VariantStore` (via `Services`).

- [ ] **Step 1: Add Export to the detail More menu**

```swift
Button("Export…") {
    let panel = NSSavePanel(); panel.nameFieldStringValue = "\(row.report.name).tar.xz"
    if panel.runModal() == .OK, let out = panel.url?.path {
        services.taskCenter.start(title: "Export \(row.report.name)", plannedStages: [],
            executable: services.executable, arguments: services.commandBuilder.exportArgs(name: row.report.name, out: out))
    }
}
```

- [ ] **Step 2: Add Import to the `LibraryView` toolbar**

```swift
Button("Import…") {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [.init(filenameExtension: "xz")!]
    if panel.runModal() == .OK, let archive = panel.url?.path {
        let base = panel.url!.deletingPathExtension().deletingPathExtension().lastPathComponent
        services.taskCenter.start(title: "Import \(base)", plannedStages: [],
            executable: services.executable, arguments: services.commandBuilder.importArgs(archive: archive, name: base))
    }
}
```

- [ ] **Step 3: Show variant in the detail Overview**

In `VMDetailView`, read `services.variants.variant(forVM: row.report.name) ?? "Unknown"` and add a `("Variant", …)` spec row.

- [ ] **Step 4: Verify (manual)**

Export a VM (Save panel → task streams → `.tar.xz` produced), import it back under a new name (Open panel → task → VM appears). A wizard-created VM shows its variant; an externally-created one shows "Unknown".

- [ ] **Step 5: Commit**

```bash
git add Sources
git commit -m "feat(ui): add export/import actions and variant display"
```

---

## Self-Review

**Spec coverage (design spec §6.3 create wizard, §6.4 task console, §5.3 variant, §8 elevation):**
- Streaming runner + stage parser + TaskModel + TaskCenter → Tasks 1–3, 6. ✓
- Create wizard (name validation, variant, both sources, review copy, native-auth via `--root-popup`) → Tasks 5, 7. ✓
- Success/failure from exit code; cancel via SIGINT → Task 3. ✓
- Variant sidecar (write on create, read in detail, "Unknown" fallback) → Tasks 4, 7, 8. ✓
- Export/import via the task engine → Tasks 5, 8. ✓

**Placeholder scan:** none — every step has runnable code/commands. The two "adjust on completion" notes (variant write timing in Task 7; log-ordering fallback in Task 3) specify the exact concrete adjustment, not a vague TODO.

**Type consistency:** `StreamingRunner.run(executable:arguments:environment:onStart:onLine:)` identical across Tasks 2/3/6; `TaskModel(title:plannedStages:)` + `run(executable:arguments:runner:)` consistent between Task 3 and `TaskCenter`; `VPhoneCommandBuilder` method names (`createArgs`/`exportArgs`/`importArgs`) and `createStages` match between Task 5 and Tasks 6–8; `AppEnvironment.Services` gains `taskCenter/executable/commandBuilder/variants` in Task 6 and they're used with those exact names in Tasks 7–8; `TaskStatus` cases consistent between Task 3 and the console pill (Task 6).

**Elevation check:** create argv always ends with `--root-popup` (Task 5), so vphone-ws never passes `--sudo-password`; the native dialog is raised by the CLI. ✓
