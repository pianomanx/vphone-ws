public struct VPhoneCommandBuilder: Sendable {
    public let libraryRoot: String?
    public init(libraryRoot: String?) { self.libraryRoot = libraryRoot }

    // Display chips (mockup task console). The CLI's `=== … ===` banners map to these.
    public static let createStages = ["Prepare", "Patch", "Restore", "Install CFW", "First boot"]

    // CLI banner (inner text of `=== … ===`) → display chip. Banners absent here
    // ("vm new", "JB Finalize", "Done", "Boot analysis") don't drive a chip.
    public static let createStageMap: [String: String] = [
        "fw prepare": "Prepare",
        "fw patch": "Patch",
        "Restore phase": "Restore",
        "CFW install (host-mount)": "Install CFW",
        "First boot": "First boot",
    ]

    public func createArgs(
        name: String, variant: String, iphoneSource: String, cloudosSource: String, diskSizeGB: Int
    ) -> [String] {
        withLibraryRoot(["vm", "create", name, "-V", variant,
                         "--iphone-source", iphoneSource, "--cloudos-source", cloudosSource,
                         "--disk-size", String(diskSizeGB), "--root-popup", "-v"])
    }

    public func exportArgs(name: String, out: String) -> [String] {
        withLibraryRoot(["vm", "export", name, "-o", out])
    }

    public func importArgs(archive: String, name: String) -> [String] {
        withLibraryRoot(["vm", "import", archive, "-n", name])
    }

    private func withLibraryRoot(_ argv: [String]) -> [String] {
        guard let libraryRoot else { return argv }
        return argv + ["--library-root", libraryRoot]
    }
}
