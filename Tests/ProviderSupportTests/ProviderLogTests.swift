import Foundation
import Testing
@testable import ProviderSupport

@Suite("Provider logging")
struct ProviderLogTests {
    @Test("A line says which provider wrote it, without being mistaken for protocol")
    func lineShape() {
        let log = ProviderLog(providerID: "cursor")
        #expect(log.line("token source=keychain") == "quota-provider-cursor: token source=keychain\n")
    }

    @Test("The provider id is its own id, not a fixed one")
    func providerIDIsUsed() {
        let log = ProviderLog(providerID: "codex")
        #expect(log.line("ready") == "quota-provider-codex: ready\n")
    }
}
