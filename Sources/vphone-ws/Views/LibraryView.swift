import AppKit
import SwiftUI
import VPhoneWSCore

struct LibraryView: View {
    let services: AppEnvironment.Services
    @State private var selection: String?
    @State private var query = ""
    @State private var readinessChecks: [HostCheck] = []
    @State private var showReadiness = false
    @State private var showCreate = false
    @State private var operationTask: TaskModel?
    @State private var actionError: String?

    private var store: VMStore { services.store }

    private var filtered: [VMRow] {
        query.isEmpty ? store.rows
            : store.rows.filter { $0.report.name.localizedCaseInsensitiveContains(query) }
    }

    private var attentionCount: Int {
        readinessChecks.filter { $0.status == .attention }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            if showCreate {
                CreateWizardView(services: services, onClose: { showCreate = false })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    sidebar.frame(width: Theme.sidebarWidth)
                    Rectangle().fill(Theme.border).frame(width: 1)
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .task {
            while !Task.isCancelled {
                await store.refresh()
                readinessChecks = await services.readiness.runAll()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .sheet(isPresented: $showReadiness) {
            HostReadinessSheet(readiness: services.readiness) { readinessChecks = $0 }
        }
        .sheet(item: $operationTask) { task in
            OperationSheet(task: task, onClose: { operationTask = nil })
        }
        .alert("Couldn't start VM", isPresented: startErrorPresented) {
            Button("OK") {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var startErrorPresented: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    private func activate(_ row: VMRow) {
        selection = row.report.name
        guard !row.isRunning else {
            Task { await services.coordinator.showScreen(name: row.report.name) }
            return
        }
        do {
            try services.coordinator.launch(name: row.report.name)
            Task { await store.refresh() }
        } catch {
            actionError = String(describing: error)
        }
    }

    private var titleBar: some View {
        HStack(spacing: 10) {
            Text("vPhone Workstation")
                .font(.ws(13, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Spacer()
            Button { showReadiness = true } label: {
                StatusPill(
                    kind: attentionCount == 0 ? .running : .warn,
                    label: attentionCount == 0 ? "Host ready" : "\(attentionCount) need attention")
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: 40)
        .background(Theme.surface2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { row in
                        SidebarRow(row: row, selected: selection == row.report.name)
                            .contentShape(.rect)
                            // Single tap selects immediately; the double-tap runs
                            // simultaneously so it doesn't hold the single tap for
                            // the double-click timeout.
                            .onTapGesture { selection = row.report.name }
                            .simultaneousGesture(TapGesture(count: 2).onEnded { activate(row) })
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
            .scrollContentBackground(.hidden)
            newVMFooter
        }
        .background(Theme.surface2)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.ws(13)).foregroundStyle(Theme.faint)
            TextField("Search VMs", text: $query)
                .textFieldStyle(.plain)
                .font(.ws(13))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.border, lineWidth: 1))
        .clipShape(.rect(cornerRadius: Theme.radiusSmall))
        .padding(12)
    }

    private var newVMFooter: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)
            HStack(spacing: 12) {
                Button { showCreate = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.ws(12, weight: .semibold))
                        Text("New VM…").font(.ws(13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                Spacer()
                Button { importVM() } label: {
                    Image(systemName: "square.and.arrow.down").font(.ws(14)).foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain).help("Import VM…")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let name = selection, let row = store.rows.first(where: { $0.report.name == name }) {
            VMDetailView(row: row, services: services, selection: $selection,
                         presentOperation: { operationTask = $0 })
                .background(Theme.bg)
        } else {
            ZStack {
                Theme.bg
                if let err = store.loadError {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 34)).foregroundStyle(Theme.warn)
                        Text("Couldn't load VMs").font(.ws(15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(err).font(.ws(12.5)).foregroundStyle(Theme.dim)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 380)
                    }
                    .padding(24)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "iphone").font(.system(size: 40)).foregroundStyle(Theme.faint)
                        Text("Select a VM").font(.ws(15)).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
    }

    private func importVM() {
        let panel = NSOpenPanel()
        if panel.runModal() == .OK, let url = panel.url {
            let base = url.deletingPathExtension().deletingPathExtension().lastPathComponent
            operationTask = services.taskCenter.start(
                title: "Import \(base)", plannedStages: [],
                executable: services.executable,
                arguments: services.commandBuilder.importArgs(archive: url.path, name: base))
        }
    }
}

private struct SidebarRow: View {
    let row: VMRow
    let selected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "iphone")
                .font(.system(size: 18))
                .foregroundStyle(selected ? Theme.accent : Theme.dim)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    StatusDot(running: row.isRunning)
                    Text(row.report.name).font(.ws(13.5, weight: .semibold)).foregroundStyle(Theme.text)
                }
                Text(row.displayVersions).font(.wsMono(11.5)).foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(selected ? Theme.accent.opacity(0.14) : Color.clear)
        .clipShape(.rect(cornerRadius: Theme.radiusSmall))
    }
}
