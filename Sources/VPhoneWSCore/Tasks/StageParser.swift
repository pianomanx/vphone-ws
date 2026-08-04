import Foundation

public enum LogEvent: Equatable, Sendable {
    case stage(String)
    case marker(String)
    case plain(String)
}

public enum StageParser {
    public static func classify(_ line: String) -> LogEvent {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("===") && t.hasSuffix("===") && t.count > 6 {
            let inner = t.dropFirst(3).dropLast(3).trimmingCharacters(in: .whitespaces)
            return .stage(String(inner))
        }
        for m in ["[*]", "[+]", "[-]", "[!]"] where t.hasPrefix(m) {
            return .marker(line)
        }
        return .plain(line)
    }
}
