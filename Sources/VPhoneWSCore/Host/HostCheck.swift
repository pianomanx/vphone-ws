public enum CheckStatus: Equatable, Sendable {
    case ok
    case attention
}

public struct HostCheck: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let status: CheckStatus
    public let detail: String
    public let fixCommand: String?

    public init(id: String, title: String, status: CheckStatus, detail: String, fixCommand: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.fixCommand = fixCommand
    }
}
