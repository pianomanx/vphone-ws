public struct FirmwareImage: Codable, Equatable, Sendable, Hashable {
    public let name: String
    public let url: String

    public init(name: String, url: String) {
        self.name = name; self.url = url
    }
}

public struct FirmwarePairing: Codable, Equatable, Sendable {
    public let ios: FirmwareImage
    public let recommendedCloudOS: FirmwareImage
}

public struct FirmwareCatalog: Codable, Equatable, Sendable {
    public let pairings: [FirmwarePairing]

    public init(pairings: [FirmwarePairing]) { self.pairings = pairings }

    public var iosImages: [FirmwareImage] { pairings.map(\.ios) }

    /// Distinct cloudOS images (dedup by url), first-seen order — the manual-mode menu.
    public var cloudOSImages: [FirmwareImage] {
        var seen = Set<String>()
        return pairings.compactMap {
            seen.insert($0.recommendedCloudOS.url).inserted ? $0.recommendedCloudOS : nil
        }
    }
}
