import Foundation
import Testing
@testable import QuotaPluginClaude

@Suite("Claude credentials")
struct CredentialTests {
    @Test("The token is read out of the OAuth block")
    func readsTheOAuthBlock() throws {
        let credential = try #require(
            ClaudeCredentialReader.credential(
                in: #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-token"}}"#
            )
        )
        #expect(credential.accessToken == "sk-ant-oat01-token")
    }

    @Test("A token written at the root is read as well")
    func readsARootToken() throws {
        let credential = try #require(
            ClaudeCredentialReader.credential(in: #"{"accessToken":"root-token"}"#)
        )
        #expect(credential.accessToken == "root-token")
    }

    @Test("A file with no OAuth block holds no credential")
    func refusesAnAPIKeySignIn() {
        #expect(
            ClaudeCredentialReader.credential(
                in: #"{"anthropicApiKey":"sk-ant-api03-key"}"#
            ) == nil
        )
    }

    @Test("An expiry in milliseconds is read in milliseconds")
    func readsMilliseconds() throws {
        let expiry = try #require(
            ClaudeCredentialReader.expiry(from: 1_759_700_000_000)
        )
        #expect(expiry == Date(timeIntervalSince1970: 1_759_700_000))
    }

    @Test("An expiry in seconds is read in seconds")
    func readsSeconds() throws {
        let expiry = try #require(ClaudeCredentialReader.expiry(from: 1_759_700_000))
        #expect(expiry == Date(timeIntervalSince1970: 1_759_700_000))
    }

    @Test("A credential whose expiry has passed is expired")
    func expiredCredential() throws {
        let credential = try #require(
            ClaudeCredentialReader.credential(
                in: #"{"claudeAiOauth":{"accessToken":"token","expiresAt":1759700000000}}"#
            )
        )
        #expect(credential.isExpired(now: Date(timeIntervalSince1970: 1_759_800_000)))
        #expect(!credential.isExpired(now: Date(timeIntervalSince1970: 1_759_600_000)))
    }

    @Test("The plan is read out of the credential")
    func readsThePlan() throws {
        let credential = try #require(
            ClaudeCredentialReader.credential(
                in: #"{"claudeAiOauth":{"accessToken":"token","subscriptionType":"max"}}"#
            )
        )
        #expect(credential.subscriptionType == "max")
    }

    @Test("The account is the email the credential names")
    func readsTheAccount() throws {
        let credential = try #require(
            ClaudeCredentialReader.credential(
                in: #"{"claudeAiOauth":{"accessToken":"token","email":"me@example.com"}}"#
            )
        )
        #expect(credential.accountLabel == "me@example.com")
    }

    @Test("A credential with no plan is still a credential")
    func toleratesAMissingPlan() throws {
        let credential = try #require(
            ClaudeCredentialReader.credential(in: #"{"claudeAiOauth":{"accessToken":"token"}}"#)
        )
        #expect(credential.subscriptionType == nil)
        #expect(credential.expiresAt == nil)
    }
}
