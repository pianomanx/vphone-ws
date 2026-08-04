import Testing
@testable import VPhoneWSCore

@Test func classifiesBannersMarkersAndPlain() {
    #expect(StageParser.classify("=== Restore phase ===") == .stage("Restore phase"))
    #expect(StageParser.classify("===   CFW install   ===") == .stage("CFW install"))
    #expect(StageParser.classify("[+] SHSH fetched") == .marker("[+] SHSH fetched"))
    #expect(StageParser.classify("[-] panic") == .marker("[-] panic"))
    #expect(StageParser.classify("uploading ramdisk") == .plain("uploading ramdisk"))
}
