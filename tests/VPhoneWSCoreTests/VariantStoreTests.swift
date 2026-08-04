import Testing
import Foundation
@testable import VPhoneWSCore

@Test func writesAndReadsVariant() throws {
    let root = NSTemporaryDirectory() + "vws-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: root + "/myvm", withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: root) }

    let store = VariantStore(libraryRoot: root)
    #expect(store.variant(forVM: "myvm") == nil)
    try store.setVariant("jb", forVM: "myvm")
    #expect(store.variant(forVM: "myvm") == "jb")
}
