import SwiftUI
import VPhoneWSCore

struct HostReadinessSheet: View {
    let readiness: HostReadiness
    var onChecks: ([HostCheck]) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var checks: [HostCheck] = []

    private var attentionCount: Int {
        checks.filter { $0.status == .attention }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(checks) { check in
                        CheckRow(check: check)
                        if check.id != checks.last?.id {
                            Divider().overlay(Theme.border)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .frame(width: 520, height: 420)
        .background(Theme.bg)
        .task {
            checks = await readiness.runAll()
            onChecks(checks)
        }
    }

    private var header: some View {
        HStack {
            Text("Host readiness")
                .font(.ws(15, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
            if !checks.isEmpty {
                StatusPill(
                    kind: attentionCount == 0 ? .running : .warn,
                    label: attentionCount == 0 ? "Host ready" : "\(attentionCount) need attention")
            }
            Button("Done") { dismiss() }.buttonStyle(.wsSecondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Theme.surface2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

private struct CheckRow: View {
    let check: HostCheck

    private var isOK: Bool { check.status == .ok }
    private var accent: Color { isOK ? Theme.good : Theme.warn }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(accent.opacity(0.16)).frame(width: 26, height: 26)
                Image(systemName: isOK ? "checkmark" : "exclamationmark.triangle.fill")
                    .font(.ws(12, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(check.title).font(.ws(14, weight: .semibold)).foregroundStyle(Theme.text)
                Text(check.detail).font(.ws(13)).foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                if let fix = check.fixCommand {
                    Text(fix).font(.wsMono(12)).foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.inset)
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.border, lineWidth: 1))
                        .clipShape(.rect(cornerRadius: Theme.radiusSmall))
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }
}
