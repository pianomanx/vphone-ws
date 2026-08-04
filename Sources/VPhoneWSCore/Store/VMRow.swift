public struct VMRow: Identifiable, Equatable, Sendable {
    public let report: VMReport
    public var isRunning: Bool
    public var id: String { report.name }

    public init(report: VMReport, isRunning: Bool) {
        self.report = report; self.isRunning = isRunning
    }

    public var displayVersions: String {
        guard let ri = report.restoreInfo else { return "—" }
        return "iOS \(ri.ios.version) · cloudOS \(ri.cloudOS.version)"
    }
}
