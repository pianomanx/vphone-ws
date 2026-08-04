import Foundation

extension VPhoneCLIClient {
    public func setConfig(name: String, cpu: Int?, memoryMB: Int?, network: String?) async throws {
        var argv = ["vm", "config", name]
        if let cpu { argv += ["--cpu", String(cpu)] }
        if let memoryMB { argv += ["--memory", String(memoryMB)] }
        if let network { argv += ["--network", network] }
        _ = try await runText(argv)
    }

    public func clone(name: String, to newName: String) async throws {
        _ = try await runText(["vm", "clone", name, newName])
    }

    public func rename(name: String, to newName: String) async throws {
        _ = try await runText(["vm", "rename", name, newName])
    }

    public func delete(name: String) async throws {
        _ = try await runText(["vm", "delete", name, "--force"])
    }
}
