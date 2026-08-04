import Testing
@testable import VPhoneWSCore

@Test func createIncludesRootPopupVerboseSourcesDiskAndLibraryRoot() {
    let b = VPhoneCommandBuilder(libraryRoot: "/lib")
    #expect(b.createArgs(name: "a", variant: "jb", iphoneSource: "26.3", cloudosSource: "26.4", diskSizeGB: 128) ==
        ["vm","create","a","-V","jb","--iphone-source","26.3","--cloudos-source","26.4","--disk-size","128","--root-popup","-v","--library-root","/lib"])
}

@Test func exportAndImportArgs() {
    let b = VPhoneCommandBuilder(libraryRoot: nil)
    #expect(b.exportArgs(name: "a", out: "/tmp/a.tar.xz") == ["vm","export","a","-o","/tmp/a.tar.xz"])
    #expect(b.importArgs(archive: "/tmp/a.tar.xz", name: "restored") == ["vm","import","-i","/tmp/a.tar.xz","-n","restored"])
}
