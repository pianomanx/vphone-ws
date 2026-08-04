import Foundation

public enum AppEnvironment {
    public static func defaultLibraryRoot() -> String {
        if let override = ProcessInfo.processInfo.environment["VPHONE_LIBRARY_ROOT"], !override.isEmpty {
            return override
        }
        return NSHomeDirectory() + "/.vphone/VMs"
    }

    public struct Services {
        public let store: VMStore
        public let coordinator: LaunchCoordinator
        public let client: VPhoneCLIClient
        public let readiness: HostReadiness
        public let taskCenter: TaskCenter
        public let executable: URL
        public let commandBuilder: VPhoneCommandBuilder
        public let variants: VariantStore
    }

    @MainActor
    public static func makeServices(explicitCLIPath: String? = nil) -> Services? {
        let location = VPhoneCLILocator().locate(
            explicit: explicitCLIPath,
            envPath: ProcessInfo.processInfo.environment["VPHONE_CLI_PATH"],
            pathLookup: VPhoneCLILocator.whichLookup,
            fileExists: FileManager.default.fileExists(atPath:))
        guard case .found(let exe) = location else { return nil }
        let runner = SystemCLIRunner()
        let root = defaultLibraryRoot()
        let probe = RunningStateProbe(runner: runner)
        let client = VPhoneCLIClient(executable: exe, libraryRoot: root, runner: runner)
        return Services(
            store: VMStore(client: client, probe: probe, libraryRoot: root),
            coordinator: LaunchCoordinator(
                executable: exe, libraryRoot: root, launcher: SystemProcessLauncher(),
                client: client, probe: probe),
            client: client,
            readiness: HostReadiness(runner: runner),
            taskCenter: TaskCenter(runner: SystemStreamingRunner()),
            executable: exe,
            commandBuilder: VPhoneCommandBuilder(libraryRoot: root),
            variants: VariantStore(libraryRoot: root))
    }
}
