import Foundation
import AppKit

@MainActor
public final class LaunchCoordinator {
    private let executable: URL
    private let libraryRoot: String?
    private let launcher: ProcessLauncher
    private let client: VPhoneCLIClient
    private let probe: RunningStateProbe

    public init(
        executable: URL, libraryRoot: String?, launcher: ProcessLauncher,
        client: VPhoneCLIClient, probe: RunningStateProbe
    ) {
        self.executable = executable
        self.libraryRoot = libraryRoot
        self.launcher = launcher
        self.client = client
        self.probe = probe
    }

    public func launch(name: String) throws {
        var argv = ["vm", "launch", name]
        if let libraryRoot { argv += ["--library-root", libraryRoot] }
        _ = try launcher.launch(executable: executable, arguments: argv, environment: nil)
    }

    public func stop(name: String) async throws {
        try await client.stop(name: name)
    }

    /// Bring the VM's GUI window forward. The window belongs to the
    /// `vphone-cli --config …/config.plist` process — NOT the Virtualization XPC
    /// helper that holds Disk.img — so match on the config path, not lsof.
    public func showScreen(name: String) async {
        let root = libraryRoot ?? AppEnvironment.defaultLibraryRoot()
        let configPath = "\(root)/\(name)/config.plist"
        guard let pid = await probe.firstPID(commandContaining: configPath),
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.unhide()
        // macOS 14+ activation is cooperative: the active app (us) must yield to
        // the target, otherwise its own activate() is ignored.
        NSApp.yieldActivation(to: app)
        app.activate()
    }
}
