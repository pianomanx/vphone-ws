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

@Test func amfiEvaluator() {
    let running = "/usr/sbin/cfprefsd\nPython -m amfidont --spoof-apple --path /Applications/vphone-cli.app\nloginwindow\n"
    #expect(HostReadiness.evalAMFI(psOutput: running, bootArgs: "").status == .ok)

    // The `vphone-amfidont` wrapper process is not the daemon itself.
    let wrapperOnly = "/bin/zsh /opt/homebrew/bin/vphone-amfidont\nloginwindow\n"
    #expect(HostReadiness.evalAMFI(psOutput: wrapperOnly, bootArgs: "").status == .attention)

    // The boot-arg alone satisfies the check even with no amfidont running.
    let viaBootArg = HostReadiness.evalAMFI(
        psOutput: "loginwindow\n", bootArgs: "boot-args\tamfi_get_out_of_my_way=1 -v\n")
    #expect(viaBootArg.status == .ok)
    #expect(viaBootArg.fixCommand == nil)

    // A zeroed boot-arg does not count.
    #expect(HostReadiness.evalAMFI(psOutput: "loginwindow\n", bootArgs: "amfi_get_out_of_my_way=0").status == .attention)

    let miss = HostReadiness.evalAMFI(psOutput: "loginwindow\nWindowServer\n", bootArgs: "")
    #expect(miss.status == .attention)
    #expect(miss.fixCommand != nil)
}

@Test func researchGuestsEvaluator() {
    #expect(HostReadiness.evalResearchGuests(csrutilOutput: "Allow Research Guests status: enabled\n").status == .ok)
    let off = HostReadiness.evalResearchGuests(csrutilOutput: "Allow Research Guests status: disabled\n")
    #expect(off.status == .attention)
    #expect(off.fixCommand == "csrutil allow-research-guests enable")
}

@Test func cliEvaluator() {
    #expect(HostReadiness.evalCLI(.found(URL(fileURLWithPath: "/opt/homebrew/bin/vphone-cli"))).status == .ok)
    #expect(HostReadiness.evalCLI(.notFound).status == .attention)
}
