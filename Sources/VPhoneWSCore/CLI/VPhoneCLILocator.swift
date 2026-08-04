import Foundation

public enum VPhoneCLILocation: Equatable, Sendable {
    case found(URL)
    case notFound
}

public struct VPhoneCLILocator: Sendable {
    /// Bundled `.app` launches inherit launchd's minimal `PATH`, which omits Homebrew's install dirs.
    public static let wellKnownPaths = ["/opt/homebrew/bin/vphone-cli", "/usr/local/bin/vphone-cli"]

    public init() {}

    public func locate(
        explicit: String?,
        envPath: String?,
        pathLookup: (String) -> URL?,
        fileExists: (String) -> Bool
    ) -> VPhoneCLILocation {
        if let explicit, !explicit.isEmpty {
            return .found(URL(fileURLWithPath: explicit))
        }
        if let envPath, !envPath.isEmpty, fileExists(envPath) {
            return .found(URL(fileURLWithPath: envPath))
        }
        if let onPath = pathLookup("vphone-cli") {
            return .found(onPath)
        }
        if let wellKnown = Self.wellKnownPaths.first(where: fileExists) {
            return .found(URL(fileURLWithPath: wellKnown))
        }
        return .notFound
    }

    public static func whichLookup(_ name: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe(); process.standardOutput = pipe
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }
}
