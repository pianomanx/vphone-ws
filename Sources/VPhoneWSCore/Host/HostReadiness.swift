import Foundation

public struct HostReadiness: Sendable {
    let runner: CLIRunner

    public init(runner: CLIRunner) {
        self.runner = runner
    }

    public static func evalNestedVM(hvVmmPresent stdout: String) -> HostCheck {
        let nested = stdout.trimmingCharacters(in: .whitespacesAndNewlines) != "0"
        return HostCheck(
            id: "nested",
            title: nested ? "Running inside a VM" : "Not running inside a VM",
            status: nested ? .attention : .ok,
            detail: nested ? "kern.hv_vmm_present = 1 — nested PV=3 guests can't boot." : "kern.hv_vmm_present = 0 — good."
        )
    }

    public static func evalMacOS(version: OperatingSystemVersion) -> HostCheck {
        let ok = version.majorVersion >= 15
        return HostCheck(
            id: "macos",
            title: "macOS 15 or newer",
            status: ok ? .ok : .attention,
            detail: "macOS \(version.majorVersion).\(version.minorVersion)"
        )
    }

    /// AMFI must be bypassed for the signed vphone-cli binary to launch. Two documented
    /// routes satisfy this: the `amfi_get_out_of_my_way=1` boot-arg (kernel-wide) or the
    /// `amfidont` daemon (per-app userspace allow). Either one passes the check.
    public static func evalAMFI(psOutput: String, bootArgs: String) -> HostCheck {
        let amfidontRunning = psOutput.split(separator: "\n").contains { line in
            line.contains("amfidont") && !line.contains("vphone-amfidont")
        }
        let bootArgSet = bootArgIsSet(bootArgs, "amfi_get_out_of_my_way")
        let ok = amfidontRunning || bootArgSet

        let title: String, detail: String
        if bootArgSet {
            title = "AMFI disabled via boot-arg"
            detail = "amfi_get_out_of_my_way=1 in boot-args — AMFI is out of the way; amfidont not needed."
        } else if amfidontRunning {
            title = "AMFI allowlist (amfidont) is running"
            detail = "amfidont is active."
        } else {
            title = "AMFI will block vphone-cli"
            detail = "Neither amfi_get_out_of_my_way=1 (boot-args) nor amfidont is active — the signed "
                + "VM binary is killed on launch. Run amfidont, or set the boot-arg and reboot."
        }
        return HostCheck(id: "amfi", title: title, status: ok ? .ok : .attention,
                         detail: detail, fixCommand: ok ? nil : "vphone-amfidont")
    }

    /// True when boot-args carries `key=<v>` with a nonzero value (1, 0x1, …).
    static func bootArgIsSet(_ bootArgs: String, _ key: String) -> Bool {
        for token in bootArgs.split(whereSeparator: { " \t\n".contains($0) }) {
            guard token.hasPrefix("\(key)=") else { continue }
            let value = token.dropFirst(key.count + 1)
            return !value.isEmpty && value != "0" && value != "0x0"
        }
        return false
    }

    /// PCC research VMs only boot when research guests are allowed (SIP subfeature).
    public static func evalResearchGuests(csrutilOutput: String) -> HostCheck {
        // `csrutil allow-research-guests status` → "Allow Research Guests status: enabled|disabled".
        let enabled = csrutilOutput.lowercased().contains("enabled")
        return HostCheck(
            id: "research-guests",
            title: enabled ? "Research guests allowed" : "Research guests not allowed",
            status: enabled ? .ok : .attention,
            detail: enabled
                ? "csrutil allow-research-guests: enabled."
                : "csrutil allow-research-guests is disabled — PCC research VMs won't boot. Enable it from Recovery.",
            fixCommand: enabled ? nil : "csrutil allow-research-guests enable"
        )
    }

    public static func evalCLI(_ location: VPhoneCLILocation) -> HostCheck {
        if case .found(let url) = location {
            return HostCheck(id: "cli", title: "vphone-cli found", status: .ok, detail: url.path)
        }
        return HostCheck(
            id: "cli",
            title: "vphone-cli not found",
            status: .attention,
            detail: "Not on PATH.",
            fixCommand: "brew install zqxwce/tap/vphone-cli"
        )
    }

    public func runAll() async -> [HostCheck] {
        async let hv = sysctl("kern.hv_vmm_present")
        async let ps = psCommands()
        async let bargs = bootArgs()
        async let rguests = researchGuests()
        let cliLoc = VPhoneCLILocator().locate(
            explicit: nil,
            envPath: nil,
            pathLookup: VPhoneCLILocator.whichLookup,
            fileExists: FileManager.default.fileExists(atPath:)
        )
        return [
            Self.evalCLI(cliLoc),
            Self.evalMacOS(version: ProcessInfo.processInfo.operatingSystemVersion),
            Self.evalNestedVM(hvVmmPresent: await hv),
            Self.evalResearchGuests(csrutilOutput: await rguests),
            Self.evalAMFI(psOutput: await ps, bootArgs: await bargs),
        ]
    }

    private func sysctl(_ key: String) async -> String {
        (try? await runner.run(
            executable: URL(fileURLWithPath: "/usr/sbin/sysctl"),
            arguments: ["-n", key],
            environment: nil
        ))?.stdout ?? ""
    }

    private func psCommands() async -> String {
        (try? await runner.run(
            executable: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-ax", "-o", "command="],
            environment: nil
        ))?.stdout ?? ""
    }

    private func bootArgs() async -> String {
        (try? await runner.run(
            executable: URL(fileURLWithPath: "/usr/sbin/nvram"),
            arguments: ["boot-args"],
            environment: nil
        ))?.stdout ?? ""
    }

    private func researchGuests() async -> String {
        (try? await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/csrutil"),
            arguments: ["allow-research-guests", "status"],
            environment: nil
        ))?.stdout ?? ""
    }
}
