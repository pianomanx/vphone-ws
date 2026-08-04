import Testing
import Foundation
@testable import VPhoneWSCore

@Test func prefersExplicitThenPathThenNotFound() {
    let loc = VPhoneCLILocator()
    let explicit = URL(fileURLWithPath: "/opt/custom/vphone-cli")

    #expect(loc.locate(explicit: explicit.path, envPath: nil, pathLookup: { _ in nil }, fileExists: { _ in false }) == .found(explicit))
    let onPath = URL(fileURLWithPath: "/opt/homebrew/bin/vphone-cli")
    #expect(loc.locate(explicit: nil, envPath: nil, pathLookup: { $0 == "vphone-cli" ? onPath : nil }, fileExists: { _ in false }) == .found(onPath))
    #expect(loc.locate(explicit: nil, envPath: nil, pathLookup: { _ in nil }, fileExists: { _ in false }) == .notFound)
}

@Test func envOverrideWinsOverPathLookup() {
    let loc = VPhoneCLILocator()
    let envPath = "/custom/env/vphone-cli"
    let onPath = URL(fileURLWithPath: "/opt/homebrew/bin/vphone-cli")

    #expect(loc.locate(
        explicit: nil,
        envPath: envPath,
        pathLookup: { $0 == "vphone-cli" ? onPath : nil },
        fileExists: { $0 == envPath }
    ) == .found(URL(fileURLWithPath: envPath)))
}

@Test func envOverrideIgnoredWhenFileMissing() {
    let loc = VPhoneCLILocator()
    let onPath = URL(fileURLWithPath: "/opt/homebrew/bin/vphone-cli")

    #expect(loc.locate(
        explicit: nil,
        envPath: "/custom/env/vphone-cli",
        pathLookup: { $0 == "vphone-cli" ? onPath : nil },
        fileExists: { _ in false }
    ) == .found(onPath))
}

@Test func wellKnownFallbackUsedWhenExplicitEnvAndPathLookupAllMiss() {
    let loc = VPhoneCLILocator()

    #expect(loc.locate(
        explicit: nil,
        envPath: nil,
        pathLookup: { _ in nil },
        fileExists: { $0 == "/usr/local/bin/vphone-cli" }
    ) == .found(URL(fileURLWithPath: "/usr/local/bin/vphone-cli")))
}

@Test func wellKnownFallbackPrefersHomebrewAppleSiliconFirst() {
    let loc = VPhoneCLILocator()

    #expect(loc.locate(
        explicit: nil,
        envPath: nil,
        pathLookup: { _ in nil },
        fileExists: { _ in true }
    ) == .found(URL(fileURLWithPath: "/opt/homebrew/bin/vphone-cli")))
}

@Test func notFoundOnlyWhenEverythingMisses() {
    let loc = VPhoneCLILocator()

    #expect(loc.locate(
        explicit: nil,
        envPath: nil,
        pathLookup: { _ in nil },
        fileExists: { _ in false }
    ) == .notFound)
}
