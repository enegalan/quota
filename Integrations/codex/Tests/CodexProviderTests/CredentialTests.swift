import Foundation
import Testing
@testable import QuotaPluginCodex

@Suite("Codex credentials")
struct CredentialTests {
    @Test("The token is read out of the nested tokens block")
    func readsNestedTokens() throws {
        let credential = try #require(
            CodexCredentialReader.credential(
                in: #"{"auth_mode":"chatgpt","tokens":{"access_token":"atk-nested","account_id":"acct-1"}}"#
            )
        )
        #expect(credential.accessToken == "atk-nested")
        #expect(credential.accountID == "acct-1")
    }

    @Test("A token written at the root is read as well")
    func readsARootToken() throws {
        let credential = try #require(
            CodexCredentialReader.credential(in: #"{"access_token":"atk-root"}"#)
        )
        #expect(credential.accessToken == "atk-root")
    }

    @Test("An API-key-only file holds no ChatGPT credential")
    func refusesAnAPIKeySignIn() {
        #expect(
            CodexCredentialReader.credential(
                in: #"{"auth_mode":"api_key","OPENAI_API_KEY":"sk-test"}"#
            ) == nil
        )
    }

    @Test("A credential whose JWT expiry has passed is expired")
    func expiredCredential() throws {
        // Header/payload for exp=1000, signature ignored by the reader.
        let token = makeUnsignedJWT(claims: ["exp": 1000])
        let credential = try #require(
            CodexCredentialReader.credential(
                in: #"{"tokens":{"access_token":"\#(token)"}}"#
            )
        )
        #expect(credential.isExpired(now: Date(timeIntervalSince1970: 2000)))
        #expect(!credential.isExpired(now: Date(timeIntervalSince1970: 500)))
    }

    @Test("The account is the email the ID token names")
    func readsTheAccount() throws {
        let idToken = makeUnsignedJWT(claims: ["email": "me@example.com"])
        let credential = try #require(
            CodexCredentialReader.credential(
                in: #"{"tokens":{"access_token":"atk","id_token":"\#(idToken)"}}"#
            )
        )
        #expect(credential.accountLabel == "me@example.com")
    }

    @Test("The keychain account mirrors Codex's home-path digest")
    func keychainAccountShape() {
        let url = URL(fileURLWithPath: "/Users/example/.codex", isDirectory: true)
        let account = CredentialStore.keychainAccount(for: url)
        #expect(account.hasPrefix("cli|"))
        #expect(account.count == 4 + 16)
    }

    /// A JWT the reader can parse without verifying a signature.
    private func makeUnsignedJWT(claims: [String: Any]) -> String {
        func encode(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(encode(["alg": "none"])).\(encode(claims)).sig"
    }
}
