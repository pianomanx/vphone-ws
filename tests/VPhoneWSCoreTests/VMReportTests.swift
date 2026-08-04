import Testing
import Foundation
@testable import VPhoneWSCore

@Test func decodesListWithAndWithoutRestoreInfo() throws {
    let json = """
    [
      {"name":"research-jb","cpuCount":8,"memoryMB":8192,"diskSizeBytes":68719476736,
       "restoreInfo":{"ios":{"version":"27.0","build":"24A5380h"},
                      "cloudOS":{"version":"26.4","build":"23E5207q"}}},
      {"name":"blank","cpuCount":8,"memoryMB":8192,"diskSizeBytes":68719476736}
    ]
    """
    let reports = try JSONDecoder().decode([VMReport].self, from: Data(json.utf8))
    #expect(reports.count == 2)
    #expect(reports[0].name == "research-jb")
    #expect(reports[0].restoreInfo?.ios.version == "27.0")
    #expect(reports[0].restoreInfo?.cloudOS.build == "23E5207q")
    #expect(reports[1].restoreInfo == nil)
}
