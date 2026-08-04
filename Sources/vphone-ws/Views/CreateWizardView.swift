import SwiftUI
import VPhoneWSCore

struct CreateWizardView: View {
    static let variants = ["less", "regular", "dev", "jb", "exp"]

    enum SourceMode: Hashable { case recommended, manual }

    let services: AppEnvironment.Services
    var onClose: () -> Void = {}
    @State private var task: TaskModel?
    @State private var step = 0
    @State private var name = ""
    @State private var variant = "regular"
    @State private var cpu: Double = 8
    @State private var memory: Double = 8192
    @State private var disk: Double = 64
    @State private var catalog: FirmwareCatalog?
    @State private var catalogError: String?
    @State private var sourceMode: SourceMode = .recommended
    @State private var selectedIOS: FirmwareImage?
    @State private var selectedCloudOS: FirmwareImage?

    private let stepTitles = ["Name", "iOS & variant", "Resources", "Review"]

    private var iphoneSource: String { selectedIOS?.url ?? "" }
    private var cloudosSource: String { selectedCloudOS?.url ?? "" }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var nameValid: Bool {
        !trimmedName.isEmpty && !trimmedName.contains("/") && !trimmedName.hasPrefix(".")
            && !services.store.rows.contains { $0.report.name == trimmedName }
    }

    private var createDisabled: Bool {
        !nameValid || iphoneSource.isEmpty || cloudosSource.isEmpty
    }

    private var canAdvance: Bool {
        switch step {
        case 0: return nameValid
        case 1: return !iphoneSource.isEmpty && !cloudosSource.isEmpty
        default: return true
        }
    }

    var body: some View {
        Group {
            if let task {
                progressView(task)
            } else {
                wizardBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task {
            do { catalog = try await services.client.fetchCatalog() }
            catch { catalogError = "Couldn't load firmware catalog: \(error)" }
        }
    }

    private var wizardBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                stepRail
                Rectangle().fill(Theme.border).frame(width: 1)
                ScrollView {
                    bodyContent
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
            }
            footer
        }
    }

    private func progressView(_ task: TaskModel) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(task.title).font(.ws(15, weight: .semibold)).foregroundStyle(Theme.text)
                TaskStatusBadge(status: task.status)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Theme.surface2)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }

            TaskLogView(task: task)
                .padding(20)

            HStack {
                Button("Export log…") { TaskLogExporter.export(task, suggestedName: trimmedName) }
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
    }

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(stepTitles.enumerated()), id: \.offset) { idx, title in
                stepItem(idx: idx, title: title)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 210, alignment: .topLeading)
        .frame(maxHeight: .infinity)
        .background(Theme.surface2)
    }

    private func stepItem(idx: Int, title: String) -> some View {
        let done = idx < step
        let now = idx == step
        return HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(done ? Theme.good : Color.clear)
                    .overlay(Circle().stroke(now ? Theme.accent : (done ? Theme.good : Theme.borderStrong), lineWidth: 1.5))
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark").font(.wsMono(10, weight: .semibold)).foregroundStyle(.white)
                } else {
                    Text("\(idx + 1)").font(.wsMono(11, weight: .semibold))
                        .foregroundStyle(now ? Theme.accent : Theme.faint)
                }
            }
            Text(title)
                .font(.ws(13.5, weight: now ? .semibold : .regular))
                .foregroundStyle(now || done ? Theme.text : Theme.faint)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 9)
        .background(now ? Theme.accent.opacity(0.10) : Color.clear)
        .clipShape(.rect(cornerRadius: Theme.radiusSmall))
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch step {
        case 0: nameStep
        case 1: variantStep
        case 2: resourcesStep
        default: reviewStep
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("Name your VM", "A short identifier used for the VM folder and CLI commands.")
            labeled("VM name") {
                wsField("e.g. research-jb", text: $name)
            }
            if !name.isEmpty && !nameValid {
                Text("Invalid or already in use")
                    .font(.ws(12)).foregroundStyle(Theme.crit)
            }
        }
    }

    private var variantStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("Choose iOS & variant", "Pick how much of iOS's security you want peeled back. You can always create another VM with a different variant.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Self.variants, id: \.self) { variantCard($0) }
            }
            firmwareSection
        }
    }

    private var firmwareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Firmware").font(.ws(12, weight: .semibold)).foregroundStyle(Theme.dim)
                Spacer()
                modeToggle
            }
            if let catalog {
                if sourceMode == .recommended {
                    labeled("Recommended pairing") {
                        firmwareMenu(
                            title: selectedPairingTitle,
                            rows: catalog.pairings.map { ("\($0.ios.name)  →  \($0.recommendedCloudOS.name)", $0) },
                            pick: { selectedIOS = $0.ios; selectedCloudOS = $0.recommendedCloudOS })
                    }
                } else {
                    labeled("iOS — userland") {
                        firmwareMenu(
                            title: selectedIOS?.name ?? "Choose iOS…",
                            rows: catalog.iosImages.map { ($0.name, $0) },
                            pick: { selectedIOS = $0 })
                    }
                    labeled("cloudOS — kernel") {
                        firmwareMenu(
                            title: selectedCloudOS?.name ?? "Choose cloudOS…",
                            rows: catalog.cloudOSImages.map { ($0.name, $0) },
                            pick: { selectedCloudOS = $0 })
                    }
                    Text("Pair any iOS with any cloudOS. Combinations outside the recommended list are untested.")
                        .font(.ws(11.5)).foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let catalogError {
                Text(catalogError).font(.ws(12)).foregroundStyle(Theme.crit)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Loading firmware catalog…").font(.ws(12)).foregroundStyle(Theme.faint)
            }
        }
    }

    private var selectedPairingTitle: String {
        guard let ios = selectedIOS, let cloud = selectedCloudOS else { return "Choose a pairing…" }
        return "\(ios.name)  →  \(cloud.name)"
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach([SourceMode.recommended, .manual], id: \.self) { mode in
                let on = sourceMode == mode
                Button { sourceMode = mode } label: {
                    Text(mode == .recommended ? "Recommended" : "Manual")
                        .font(.ws(12, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Theme.accentInk : Theme.dim)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(on ? Theme.accent : Color.clear)
                        .contentShape(.rect)
                }.buttonStyle(.plain)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.borderStrong, lineWidth: 1))
        .clipShape(.rect(cornerRadius: Theme.radiusSmall))
    }

    private func firmwareMenu<Value>(
        title: String, rows: [(String, Value)], pick: @escaping (Value) -> Void
    ) -> some View {
        Menu {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Button(row.0) { pick(row.1) }
            }
        } label: {
            HStack {
                Text(title).font(.wsMono(13)).foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down").font(.ws(11)).foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(Theme.inset)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.border, lineWidth: 1))
            .clipShape(.rect(cornerRadius: Theme.radiusSmall))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var resourcesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("Resources", "Set the VM's CPU, memory, and disk size. CPU and memory can be changed later in Settings; disk is fixed once the VM is created.")
            labeled("CPU cores") {
                WSStepper(value: $cpu, range: 1...32, step: 1) { "\($0) cores" }
            }
            labeled("Memory") {
                WSStepper(value: $memory, range: 1024...65536, step: 1024) { "\($0) MB" }
            }
            labeled("Disk size") {
                WSStepper(value: $disk, range: 16...512, step: 16) { "\($0) GB" }
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader("Review & create", "Confirm the plan below, then create.")
            SpecGrid(specs: [
                ("Name", .text(trimmedName.isEmpty ? "—" : trimmedName)),
                ("Variant", .variantBadge(variant)),
                ("iOS", .text(selectedIOS?.name ?? "—")),
                ("cloudOS", .text(selectedCloudOS?.name ?? "—")),
                ("CPU", .text("\(Int(cpu)) cores")),
                ("Memory", .text("\(Int(memory)) MB")),
                ("Disk", .text("\(Int(disk)) GB")),
            ])
            reviewCallout
        }
    }

    private var reviewCallout: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "info.circle").font(.ws(15)).foregroundStyle(Theme.accent)
            Text("Creating downloads multi-GB IPSWs, asks you to authenticate once via the native macOS prompt (for the CFW host-mount), and takes several minutes. Progress runs live in the Task console.")
                .font(.ws(13)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.14))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.accent.opacity(0.28), lineWidth: 1))
        .clipShape(.rect(cornerRadius: Theme.radiusSmall))
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { onClose() }.buttonStyle(.wsSecondary)
            Spacer()
            if step > 0 {
                Button("Back") { step -= 1 }.buttonStyle(.wsSecondary)
            }
            if step < stepTitles.count - 1 {
                Button("Continue") { step += 1 }.buttonStyle(.wsPrimary).disabled(!canAdvance)
            } else {
                Button("Create") { startCreate() }.buttonStyle(.wsPrimary).disabled(createDisabled)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Theme.surface2)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func stepHeader(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.ws(18, weight: .semibold)).foregroundStyle(Theme.text)
            Text(sub).font(.ws(13.5)).foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.ws(12, weight: .semibold)).foregroundStyle(Theme.dim)
            content()
        }
    }

    private func wsField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.wsMono(13))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(Theme.inset)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.border, lineWidth: 1))
            .clipShape(.rect(cornerRadius: Theme.radiusSmall))
    }

    private func variantCard(_ v: String) -> some View {
        let meta = variantMeta(v)
        let selected = variant == v
        return Button {
            variant = v
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(meta.title).font(.ws(14, weight: .semibold)).foregroundStyle(Theme.text)
                Text(meta.desc).font(.ws(12)).foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                securityMeter(meta.level)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(selected ? Theme.accent.opacity(0.14) : Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(selected ? Theme.accent : Theme.border, lineWidth: 1))
            .clipShape(.rect(cornerRadius: Theme.radiusSmall))
        }
        .buttonStyle(.plain)
    }

    private func securityMeter(_ level: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < level ? Theme.accent : Theme.borderStrong)
                    .frame(height: 4)
            }
        }
        .padding(.top, 2)
    }

    private func variantMeta(_ v: String) -> (title: String, desc: String, level: Int) {
        switch v {
        case "less": return ("Less", "Minimal patch set — closest to stock, fewest bypasses.", 1)
        case "regular": return ("Regular", "Boots stock-like iOS with core bypasses. Best starting point.", 2)
        case "dev": return ("Developer", "Adds entitlement & debug bypass for tooling.", 3)
        case "jb": return ("Jailbreak", "Full JB — Sileo & TrollStore auto-install on first boot.", 4)
        default: return ("Experimental", "JB + anti-VM-detection research patches.", 5)
        }
    }

    private func startCreate() {
        let trimmed = trimmedName
        let args = services.commandBuilder.createArgs(
            name: trimmed, variant: variant, iphoneSource: iphoneSource, cloudosSource: cloudosSource,
            diskSizeGB: Int(disk))
        let model = services.taskCenter.start(
            title: "Create \(trimmed) · \(variant)",
            plannedStages: VPhoneCommandBuilder.createStages,
            stageMap: VPhoneCommandBuilder.createStageMap,
            executable: services.executable,
            arguments: args)
        let createdName = trimmed
        let createdVariant = variant
        let createdCPU = Int(cpu)
        let createdMemory = Int(memory)
        Task {
            while model.status == .running {
                try? await Task.sleep(for: .milliseconds(500))
            }
            if model.status == .succeeded {
                try? services.variants.setVariant(createdVariant, forVM: createdName)
                // vm create has no resource flags — apply the chosen CPU/memory to the
                // fresh bundle via vm config (effective on the first user launch).
                try? await services.client.setConfig(
                    name: createdName, cpu: createdCPU, memoryMB: createdMemory, network: nil)
                await services.store.refresh()
            }
        }
        task = model
    }
}
