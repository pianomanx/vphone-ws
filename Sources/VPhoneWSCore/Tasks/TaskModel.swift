import Foundation
import Observation

public enum TaskStatus: Equatable, Sendable {
    case running
    case succeeded
    case cancelled
    case failed(Int32)
}

/// One stage's worth of output, grouped under its `=== banner ===`. `liveLine`
/// is the in-progress line being overwritten by a progress bar's `\r` updates;
/// it commits into `lines` when a newline arrives or the stage ends.
public struct LogSegment: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public var lines: [String]
    public var liveLine: String?
    public var isDone: Bool
}

@MainActor
@Observable
public final class TaskModel: Identifiable {
    public let id = UUID()
    public let title: String
    public let plannedStages: [String]
    public private(set) var currentStage: String?
    public private(set) var completedStages: [String] = []
    public private(set) var segments: [LogSegment] = []
    public private(set) var status: TaskStatus = .running

    public var logLines: [String] { segments.flatMap(\.lines) }

    /// Full log as shareable text, grouped under each stage banner.
    public var exportText: String {
        var out = "\(title)\n\n"
        for seg in segments {
            out += "=== \(seg.title) ===\n"
            for line in seg.lines { out += line + "\n" }
            if let live = seg.liveLine { out += live + "\n" }
            out += "\n"
        }
        return out
    }

    private let stageMap: [String: String]
    private var pid: Int32?

    public init(title: String, plannedStages: [String], stageMap: [String: String] = [:]) {
        self.title = title
        self.plannedStages = plannedStages
        self.stageMap = stageMap
    }

    public func run(executable: URL, arguments: [String], runner: StreamingRunner) async {
        let (stream, continuation) = AsyncStream<StreamEvent>.makeStream(of: StreamEvent.self)
        let runTask = Task {
            let code = (try? await runner.run(
                executable: executable,
                arguments: arguments,
                environment: nil,
                onStart: { [weak self] pid in
                    Task { @MainActor in self?.pid = pid }
                },
                onEvent: { event in continuation.yield(event) }
            )) ?? -1
            continuation.finish()
            return code
        }

        for await event in stream {
            handle(event)
        }

        let code = await runTask.value
        if status != .cancelled {
            if code == 0 {
                if let current = currentStage {
                    completedStages.append(current)
                    currentStage = nil
                }
                finishLastSegment()
                status = .succeeded
            } else {
                status = .failed(code)
            }
        }
    }

    public func cancel() {
        if let pid {
            kill(pid, SIGINT)
        }
        status = .cancelled
    }

    private func handle(_ event: StreamEvent) {
        switch event {
        case .line(let raw):
            switch StageParser.classify(raw) {
            case .stage(let banner):
                let display = stageMap[banner] ?? banner
                // Chips track only the planned stages; setup/teardown banners
                // (vm new, Done, …) still open their own log segment.
                if plannedStages.isEmpty || plannedStages.contains(display) {
                    if let current = currentStage { completedStages.append(current) }
                    currentStage = display
                }
                finishLastSegment()
                segments.append(LogSegment(id: segments.count, title: display, lines: [], liveLine: nil, isDone: false))
            case .marker, .plain:
                ensureSegment()
                segments[segments.count - 1].lines.append(raw)
                segments[segments.count - 1].liveLine = nil
            }
        case .update(let text):
            ensureSegment()
            segments[segments.count - 1].liveLine = text
        }
    }

    private func ensureSegment() {
        if segments.isEmpty {
            segments.append(LogSegment(id: 0, title: "Starting up", lines: [], liveLine: nil, isDone: false))
        }
    }

    private func finishLastSegment() {
        guard !segments.isEmpty else { return }
        let i = segments.count - 1
        if let live = segments[i].liveLine {
            segments[i].lines.append(live)
            segments[i].liveLine = nil
        }
        segments[i].isDone = true
    }
}
