import Foundation
import Testing
@testable import VPhoneWSCore

@Test func decodesCatalogAndDerivesOptions() throws {
    let json = """
    {"pairings":[
      {"ios":{"name":"iOS 26.3","url":"u-ios-263"},"recommendedCloudOS":{"name":"cloudOS 26.3","url":"u-cos-263"}},
      {"ios":{"name":"iOS 26.3.1","url":"u-ios-2631"},"recommendedCloudOS":{"name":"cloudOS 26.3","url":"u-cos-263"}},
      {"ios":{"name":"iOS 26.4","url":"u-ios-264"},"recommendedCloudOS":{"name":"cloudOS 26.4","url":"u-cos-264"}}
    ]}
    """
    let cat = try JSONDecoder().decode(FirmwareCatalog.self, from: Data(json.utf8))
    #expect(cat.pairings.count == 3)
    #expect(cat.pairings[0].recommendedCloudOS.url == "u-cos-263")
    #expect(cat.iosImages.map(\.name) == ["iOS 26.3", "iOS 26.3.1", "iOS 26.4"])
    // cloudOS deduped by url, first-seen order (263 appears twice → once).
    #expect(cat.cloudOSImages.map(\.name) == ["cloudOS 26.3", "cloudOS 26.4"])
}

@Test func fetchCatalogRunsWithoutLibraryRoot() async throws {
    let fake = FakeCLIRunner()
    let exe = URL(fileURLWithPath: "/usr/bin/vphone-cli")
    fake.stub(arguments: ["fw", "catalog", "--json"],
              result: CLIResult(stdout: #"{"pairings":[]}"#, stderr: "", exitCode: 0))
    let client = VPhoneCLIClient(executable: exe, libraryRoot: "/lib", runner: fake)

    let cat = try await client.fetchCatalog()

    #expect(cat.pairings.isEmpty)
    // `fw catalog` rejects --library-root; the call must not append it.
    #expect(fake.calls.last?.arguments == ["fw", "catalog", "--json"])
}
