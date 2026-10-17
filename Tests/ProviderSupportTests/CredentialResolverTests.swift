import Foundation
import PluginKit
import Testing
@testable import ProviderSupport

@Suite("Credential resolution")
struct CredentialResolverTests {
    @Test("The first source that produces a credential that validates wins")
    func firstValidWins() throws {
        let resolved = try CredentialResolver.resolve(
            sources: [
                (.stateDatabase, { nil }),
                (.keychain, { "keychain-token" }),
                (.credentialsFile, { "file-token" }),
            ],
            validate: { $0 }
        )

        #expect(resolved.rawToken == "keychain-token")
        #expect(resolved.source == .keychain)
    }

    @Test("A source that produces nothing is passed over, not reported")
    func emptySourceSkipped() throws {
        let resolved = try CredentialResolver.resolve(
            sources: [
                (.credentialsFile, { "" }),
                (.keychain, { "the-real-one" }),
            ],
            validate: { $0 }
        )
        #expect(resolved.rawToken == "the-real-one")
    }

    @Test("A source that throws while being read is a source that is not there")
    func throwingSourceSkipped() throws {
        struct ReadFailed: Error {}
        let resolved = try CredentialResolver.resolve(
            sources: [
                (.stateDatabase, { throw ReadFailed() }),
                (.keychain, { "works" }),
            ],
            validate: { $0 }
        )
        #expect(resolved.rawToken == "works")
    }

    @Test("A credential that validates wins even when an earlier one was refused")
    func refusedThenValid() throws {
        struct Expired: Error {}
        let resolved = try CredentialResolver.resolve(
            sources: [
                (.keychain, { "expired-token" }),
                (.credentialsFile, { "fresh-token" }),
            ],
            validate: { token in
                if token == "expired-token" {
                    throw Expired()
                }
                return token
            }
        )
        #expect(resolved.rawToken == "fresh-token")
    }

    @Test("With nothing that validates, the last refusal is what is reported")
    func refusalsAreRemembered() {
        struct Expired: Error {}
        struct Refused: Error {}

        do {
            _ = try CredentialResolver.resolve(
                sources: [
                    (.keychain, { "first" }),
                    (.credentialsFile, { "second" }),
                ],
                validate: { token in
                    if token == "first" {
                        throw Expired()
                    }
                    throw Refused()
                }
            )
            Issue.record("expected a failure")
        } catch CredentialResolver.ResolutionError.rejected(let error) {
            #expect(error is Refused)
        } catch {
            Issue.record("expected a rejection, got \(error)")
        }
    }

    @Test("With no credential at all there is nothing to refuse: notFound, read as a sign-in")
    func nothingFound() {
        do {
            _ = try CredentialResolver.resolve(
                sources: [(.keychain, { nil })],
                validate: { $0 }
            )
            Issue.record("expected a failure")
        } catch CredentialResolver.ResolutionError.notFound {
            #expect(
                CredentialResolver.ResolutionError.notFound.providerError.code == .notAuthenticated
            )
        } catch {
            Issue.record("expected notFound, got \(error)")
        }
    }

    @Test("A refusal reads as a failed sign-in, whatever refused it")
    func rejectionIsAuthentication() {
        struct Refused: Error {}
        #expect(
            CredentialResolver.ResolutionError.rejected(Refused()).providerError.code
                == .authenticationFailed
        )
    }

    @Test("The token source is named, so a log can say where it came from")
    func sourceNaming() {
        #expect(CredentialSource.stateDatabase.rawValue == "stateDatabase")
        #expect(CredentialSource.keychain.rawValue == "keychain")
        #expect(CredentialSource.credentialsFile.rawValue == "credentialsFile")
        // A provider may name a source of its own without asking permission.
        #expect(CredentialSource(rawValue: "browserSession").rawValue == "browserSession")
    }
}
