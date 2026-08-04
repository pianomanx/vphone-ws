import Foundation

public struct VariantStore: Sendable {
    private struct Sidecar: Codable { let variant: String }
    private let libraryRoot: String
    public init(libraryRoot: String) { self.libraryRoot = libraryRoot }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "\(libraryRoot)/\(name)/.vphone-ws.json")
    }

    public func setVariant(_ variant: String, forVM name: String) throws {
        let data = try JSONEncoder().encode(Sidecar(variant: variant))
        try data.write(to: url(name))
    }

    public func variant(forVM name: String) -> String? {
        guard let data = try? Data(contentsOf: url(name)),
              let side = try? JSONDecoder().decode(Sidecar.self, from: data) else { return nil }
        return side.variant
    }
}
