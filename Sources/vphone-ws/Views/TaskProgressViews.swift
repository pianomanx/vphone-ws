import AppKit
import SwiftUI
import VPhoneWSCore

/// Status pill for a task (Running / Done / Cancelled / Failed).
struct TaskStatusBadge: View {
    let status: TaskStatus

    var body: some View {
        switch status {
        case .running: StatusPill(kind: .warn, label: "Running")
        case .succeeded: StatusPill(kind: .running, label: "Done")
        case .cancelled: StatusPill(kind: .stopped, label: "Cancelled")
        case .failed(let code): critPill("Failed (\(code))")
        }
    }

    private func critPill(_ label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.crit).frame(width: 7, height: 7)
            Text(label).font(.ws(12, weight: .semibold))
        }
        .foregroundStyle(Theme.crit)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Theme.crit.opacity(0.16))
        .overlay(Capsule().stroke(Theme.crit.opacity(0.3), lineWidth: 1))
        .clipShape(.capsule)
    }
}

/// Stage chips + the grouped, auto-scrolling log for one task. Fills its
/// container so it grows with a resizable window.
struct TaskLogView: View {
    let task: TaskModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !task.plannedStages.isEmpty {
                HStack(spacing: 6) {
                    ForEach(task.plannedStages, id: \.self) { stage in
                        StageChip(label: stage, state: chipState(stage))
                    }
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    logBody
                    Color.clear.frame(height: 1).id("logBottom")
                }
                .scrollContentBackground(.hidden)
                .background(Theme.logBackground)
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.border, lineWidth: 1))
                .clipShape(.rect(cornerRadius: Theme.radiusSmall))
                .onChange(of: task.segments) { _, _ in
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder private var logBody: some View {
        if task.segments.isEmpty {
            Text(task.status == .running ? "Working…" : " ")
                .font(.wsMono(12)).foregroundStyle(Theme.logText.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(task.segments.enumerated()), id: \.element.id) { idx, seg in
                    segmentSection(seg)
                    if idx < task.segments.count - 1 {
                        Rectangle().fill(Theme.border).frame(height: 1)
                    }
                }
            }
        }
    }

    private func segmentSection(_ seg: LogSegment) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                segmentGlyph(seg)
                Text(seg.title)
                    .font(.wsMono(11.5, weight: .semibold))
                    .foregroundStyle(seg.isDone ? Theme.dim : Theme.text)
            }
            if !seg.lines.isEmpty || seg.liveLine != nil {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(seg.lines.suffix(400).enumerated()), id: \.offset) { _, line in
                        logLine(line)
                    }
                    if let live = seg.liveLine { logLine(live) }
                }
                .padding(.leading, 19)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func logLine(_ line: String) -> some View {
        Text(line.isEmpty ? " " : line)
            .font(.wsMono(12))
            .foregroundStyle(lineColor(line))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func segmentGlyph(_ seg: LogSegment) -> some View {
        let (symbol, color): (String, Color) = {
            if seg.isDone { return ("✓", Theme.good) }
            switch task.status {
            case .running: return ("▸", Theme.accent)
            case .failed: return ("✕", Theme.crit)
            case .cancelled: return ("–", Theme.faint)
            case .succeeded: return ("✓", Theme.good)
            }
        }()
        return Text(symbol).font(.wsMono(11, weight: .semibold)).foregroundStyle(color).frame(width: 12)
    }

    private func chipState(_ stage: String) -> StageChip.State {
        if task.completedStages.contains(stage) { return .completed }
        if task.currentStage == stage { return .current }
        return .pending
    }

    private func lineColor(_ line: String) -> Color {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("===") && t.hasSuffix("===") { return Theme.accent }
        if line.hasPrefix("[+]") { return Theme.good }
        if line.hasPrefix("[i]") { return Theme.accent }
        if line.hasPrefix("[*]") { return Theme.dim }
        if line.hasPrefix("[-]") || line.hasPrefix("[!]") { return Theme.crit }
        return Theme.logText
    }
}

/// Progress for a one-off operation (export/import) shown as a sheet.
struct OperationSheet: View {
    let task: TaskModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(task.title).font(.ws(15, weight: .semibold)).foregroundStyle(Theme.text)
                TaskStatusBadge(status: task.status)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Theme.surface2)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }

            TaskLogView(task: task).padding(20)

            HStack {
                Button("Export log…") { TaskLogExporter.export(task, suggestedName: task.title) }
                    .buttonStyle(.wsSecondary)
                Spacer()
                if task.status == .running {
                    Button("Cancel") { task.cancel() }.buttonStyle(.wsDanger)
                } else {
                    Button("Done") { onClose() }.buttonStyle(.wsPrimary)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Theme.surface2)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
        .frame(width: 640, height: 460)
        .background(Theme.bg)
    }
}

enum TaskLogExporter {
    /// Save the task's full log to a user-chosen `.log` file.
    @MainActor static func export(_ task: TaskModel, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedName).log"
        panel.allowedContentTypes = [.init(filenameExtension: "log") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? task.exportText.write(to: url, atomically: true, encoding: .utf8)
    }
}
