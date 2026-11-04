import Foundation
import Testing
@testable import ProviderSupport

@Suite("Keychain reader")
struct KeychainReaderTests {
    @Test("The security tool is asked for the password alone")
    func securityArgumentsPrintOnlyThePassword() {
        #expect(
            KeychainReader.securityArguments(service: "Claude Code-credentials")
                == ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        )
    }

    @Test("An account narrows the item without changing the password-only flag")
    func securityArgumentsIncludeAccount() {
        #expect(
            KeychainReader.securityArguments(service: "Codex Auth", account: "cli|abcd")
                == ["find-generic-password", "-s", "Codex Auth", "-a", "cli|abcd", "-w"]
        )
    }
}
