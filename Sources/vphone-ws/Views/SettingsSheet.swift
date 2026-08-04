import SwiftUI
import VPhoneWSCore

struct SettingsSheet: View {
    // vm config --network accepts only nat | bridged | none (hostOnly is rejected).
    static let networkOptions: [(value: String, label: String)] = [
        ("nat", "NAT"), ("bridged", "Bridged"), ("none", "None"),
    ]

    let row: VMRow
    let services: AppEnvironment.Services
    @Environment(\.dismiss) private var dismiss
    @State private var cpu: Double
    @State private var memory: Double
    @State private var network: String
    @State private var actionError: String?

    init(row: VMRow, services: AppEnvironment.Services) {
        self.row = row
        self.services = services
        _cpu = State(initialValue: Double(row.report.cpuCount))
        _memory = State(initialValue: Double(row.report.memoryMB))
        _network = State(initialValue: row.report.network?.mode ?? "nat")
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    private var fixedSpecs: [(String, SpecValue)] {
        [("Disk", .text("\(row.report.diskSizeBytes / 1_073_741_824) GB"))]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("CPU cores") {
                        WSStepper(value: $cpu, range: 1...32, step: 1) { "\($0) cores" }
                    }
                    field("Memory") {
                        WSStepper(value: $memory, range: 1024...65536, step: 1024) { "\($0) MB" }
                    }
                    field("Network") {
                        wsSegmented(selection: $network, options: Self.networkOptions)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Fixed at build time")
                        SpecGrid(specs: fixedSpecs)
                    }
                    .padding(.top, 4)
                    Text("Applies on next boot; the VM must be stopped.")
                        .font(.ws(12)).foregroundStyle(Theme.faint)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            footer
        }
        .frame(width: 420)
        .background(Theme.bg)
        .focusEffectDisabled()
        .alert("Couldn't save settings", isPresented: errorPresented) {
            Button("OK") {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var header: some View {
        HStack {
            Text("\(row.report.name) — Settings")
                .font(.ws(15, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Theme.surface2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }.buttonStyle(.wsSecondary)
            Spacer()
            Button("Save") { save() }.buttonStyle(.wsPrimary).disabled(row.isRunning)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Theme.surface2)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.ws(12, weight: .semibold)).foregroundStyle(Theme.dim)
            content()
        }
    }

    private func wsSegmented(selection: Binding<String>, options: [(value: String, label: String)]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.value) { index, opt in
                let on = selection.wrappedValue == opt.value
                Button { selection.wrappedValue = opt.value } label: {
                    Text(opt.label)
                        .font(.ws(13, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Theme.accentInk : Theme.dim)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(on ? Theme.accent : Color.clear)
                        .contentShape(.rect)
                }.buttonStyle(.plain)
                if index < options.count - 1 {
                    Rectangle().fill(Theme.borderStrong).frame(width: 1)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.borderStrong, lineWidth: 1))
        .clipShape(.rect(cornerRadius: Theme.radiusSmall))
    }

    private func save() {
        Task {
            do {
                try await services.client.setConfig(
                    name: row.report.name,
                    cpu: Int(cpu),
                    memoryMB: Int(memory),
                    network: network)
                await services.store.refresh()
                dismiss()
            } catch {
                actionError = String(describing: error)
            }
        }
    }
}
