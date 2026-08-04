import AppKit
import SwiftUI
import VPhoneWSCore

struct VMDetailView: View {
    let row: VMRow
    let services: AppEnvironment.Services
    @Binding var selection: String?
    var presentOperation: (TaskModel) -> Void = { _ in }

    @State private var showSettings = false
    @State private var confirmDelete = false
    @State private var showCloneAlert = false
    @State private var showRenameAlert = false
    @State private var newName = ""
    @State private var actionError: String?

    private var errorPresented: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    private var specs: [(String, SpecValue)] {
        let r = row.report
        let variant = r.restoreInfo?.variant ?? services.variants.variant(forVM: r.name)
        return [
            ("iOS", .text(r.restoreInfo.map { "\($0.ios.version) (\($0.ios.build))" } ?? "—")),
            ("cloudOS", .text(r.restoreInfo.map { "\($0.cloudOS.version) (\($0.cloudOS.build))" } ?? "—")),
            ("Variant", variant.map { .variantBadge($0) } ?? .text("Unknown")),
            ("CPU", .text("\(r.cpuCount) cores")),
            ("Memory", .text("\(r.memoryMB) MB")),
            ("Disk", .text("\(r.diskSizeBytes / 1_073_741_824) GB")),
            ("Network", .text(Self.networkLabel(r.network))),
            ("Device", .mono(r.restoreInfo?.device ?? "Unknown")),
            ("UDID", .mono(r.udid ?? "Unknown")),
        ]
    }

    static func networkLabel(_ network: NetworkInfo?) -> String {
        guard let network else { return "Unknown" }
        switch network.mode {
        case "nat": return "NAT"
        case "bridged": return "Bridged"
        case "hostOnly": return "Host-Only"
        case "none": return "Off"
        default: return network.mode
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                callout
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Overview")
                    SpecGridSpanning(specs: specs, columns: 5, wideKeys: ["UDID"])
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .sheet(isPresented: $showSettings) { SettingsSheet(row: row, services: services) }
        .confirmationDialog(
            "Delete \(row.report.name)?", isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await services.client.delete(name: row.report.name)
                        selection = nil
                        await services.store.refresh()
                    } catch { actionError = String(describing: error) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the VM and its disk image.")
        }
        .alert("Clone \(row.report.name)", isPresented: $showCloneAlert) {
            TextField("New name", text: $newName)
            Button("Clone") {
                Task {
                    do {
                        try await services.client.clone(name: row.report.name, to: newName)
                        await services.store.refresh()
                    } catch { actionError = String(describing: error) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename \(row.report.name)", isPresented: $showRenameAlert) {
            TextField("New name", text: $newName)
            Button("Rename") {
                Task {
                    do {
                        try await services.client.rename(name: row.report.name, to: newName)
                        selection = newName
                        await services.store.refresh()
                    } catch { actionError = String(describing: error) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Action failed", isPresented: errorPresented) {
            Button("OK") {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(row.report.name).font(.ws(24, weight: .bold)).foregroundStyle(Theme.text)
                        .lineLimit(1).truncationMode(.tail)
                    StatusPill(
                        kind: row.isRunning ? .running : .stopped,
                        label: row.isRunning ? "Running" : "Stopped")
                }
                Text("~/.vphone/VMs/\(row.report.name)")
                    .font(.wsMono(12)).foregroundStyle(Theme.faint)
                    .lineLimit(1).truncationMode(.middle)
            }
            HStack(spacing: 8) {
                actionRow
                Spacer(minLength: 0)
            }
        }
    }

    private var callout: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "info.circle").font(.ws(15)).foregroundStyle(Theme.accent)
            Text("The iPhone screen opens in its own window. vPhone Workstation manages this VM; the live display, touch, and menus are handled by vphone-cli. “Show screen” brings that window forward.")
                .font(.ws(13)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.14))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.accent.opacity(0.28), lineWidth: 1))
        .clipShape(.rect(cornerRadius: Theme.radiusSmall))
    }

    @ViewBuilder
    private var actionRow: some View {
        if row.isRunning {
            Button {
                Task {
                    do {
                        try await services.coordinator.stop(name: row.report.name)
                        await services.store.refresh()
                    } catch { actionError = String(describing: error) }
                }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }.buttonStyle(.wsDanger)
            Button {
                Task { await services.coordinator.showScreen(name: row.report.name) }
            } label: {
                Label("Show screen", systemImage: "macwindow")
            }.buttonStyle(.wsSecondary)
        } else {
            Button {
                do {
                    try services.coordinator.launch(name: row.report.name)
                    Task { await services.store.refresh() }
                } catch { actionError = String(describing: error) }
            } label: {
                Label("Start", systemImage: "play.fill")
            }.buttonStyle(.wsPrimary)
        }
        Button("Settings") { showSettings = true }.buttonStyle(.wsSecondary)
        Button("Clone") { newName = ""; showCloneAlert = true }.buttonStyle(.wsSecondary)
        Button("Rename") { newName = ""; showRenameAlert = true }.buttonStyle(.wsSecondary)
        Button("Export") { exportVM() }.buttonStyle(.wsSecondary)
        Button("Delete") { confirmDelete = true }.buttonStyle(.wsDanger)
    }

    private func exportVM() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(row.report.name).tar.xz"
        if panel.runModal() == .OK, let out = panel.url?.path {
            presentOperation(services.taskCenter.start(
                title: "Export \(row.report.name)", plannedStages: [],
                executable: services.executable,
                arguments: services.commandBuilder.exportArgs(name: row.report.name, out: out)))
        }
    }
}
