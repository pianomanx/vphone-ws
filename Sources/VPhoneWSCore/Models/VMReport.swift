public struct OSVersion: Codable, Equatable, Sendable {
    public let version: String
    public let build: String
}

public struct RestoreInfo: Codable, Equatable, Sendable {
    public let ios: OSVersion
    public let cloudOS: OSVersion
    public let device: String?
    public let variant: String?

    public init(ios: OSVersion, cloudOS: OSVersion, device: String? = nil, variant: String? = nil) {
        self.ios = ios; self.cloudOS = cloudOS; self.device = device; self.variant = variant
    }
}

public struct NetworkInfo: Codable, Equatable, Sendable {
    public let mode: String
    public let macAddress: String?
    public let bridgeInterface: String?
}

public struct VMReport: Codable, Equatable, Sendable {
    public let name: String
    public let cpuCount: Int
    public let memoryMB: Int
    public let diskSizeBytes: Int64
    public let network: NetworkInfo?
    public let udid: String?
    public let restoreInfo: RestoreInfo?

    public init(
        name: String, cpuCount: Int, memoryMB: Int, diskSizeBytes: Int64,
        network: NetworkInfo? = nil, udid: String? = nil, restoreInfo: RestoreInfo? = nil
    ) {
        self.name = name
        self.cpuCount = cpuCount
        self.memoryMB = memoryMB
        self.diskSizeBytes = diskSizeBytes
        self.network = network
        self.udid = udid
        self.restoreInfo = restoreInfo
    }
}
