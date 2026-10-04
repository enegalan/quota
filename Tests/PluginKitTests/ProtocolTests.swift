import Foundation
import Testing
@testable import PluginKit

@Suite("Protocol shapes")
struct ProtocolShapeTests {
    // MARK: Requests

    @Test("A request round trips through JSON")
    func requestRoundTrip() throws {
        let request = PluginRequest(
            id: "req-1",
            method: .fetchUsage,
            payload: .fetchUsage(FetchUsageRequest(localDate: "2026-09-25"))
        )
        let data = try PluginJSON.encoder.encode(request)
        #expect(try PluginJSON.decoder.decode(PluginRequest.self, from: data) == request)
    }

    @Test("A request with no payload round trips, and does not grow a null")
    func requestWithoutPayloadRoundTrip() throws {
        let request = PluginRequest(id: "req-1", method: .describe)
        let data = try PluginJSON.encoder.encode(request)
        let text = try #require(String(bytes: data, encoding: .utf8))
        #expect(try PluginJSON.decoder.decode(PluginRequest.self, from: data) == request)
        #expect(!text.contains("payload"))
    }

    @Test("Every method is spelled the way the host expects")
    func methodRawValues() {
        #expect(PluginMethod.describe.rawValue == "describe")
        #expect(PluginMethod.connect.rawValue == "connect")
        #expect(PluginMethod.disconnect.rawValue == "disconnect")
        #expect(PluginMethod.fetchUsage.rawValue == "fetchUsage")
        #expect(PluginMethod.allCases.count == 4)
    }

    @Test("A method the host does not have cannot be encoded, so it cannot be sent")
    func unknownMethodFailsToDecode() throws {
        let json = #"{"id":"req-1","method":"deleteEverything"}"#
        #expect(throws: (any Error).self) {
            try PluginJSON.decoder.decode(PluginRequest.self, from: Data(json.utf8))
        }
    }

    // MARK: Responses

    @Test("A successful response round trips through JSON")
    func successRoundTrip() throws {
        let response = PluginResponse(
            id: "req-1",
            result: .success(.usage(UsageResult(
                quotas: [ProviderUsage(
                    externalID: "ext-1",
                    displayName: "Cursor",
                    bucketID: "models",
                    bucketDisplayName: "Models",
                    usagePercentage: 42.5,
                    periodStart: "2026-09-01",
                    periodEnd: "2026-09-30",
                    updatedAt: "2026-09-25T10:00:00Z"
                )],
                supportsHistorical: true
            )))
        )
        let data = try PluginJSON.encoder.encode(response)
        #expect(try PluginJSON.decoder.decode(PluginResponse.self, from: data) == response)
    }

    @Test("A failed response round trips through JSON")
    func failureRoundTrip() throws {
        let response = PluginResponse(
            id: "req-1",
            result: .failure(ProviderError(code: .notAuthenticated))
        )
        let data = try PluginJSON.encoder.encode(response)
        #expect(try PluginJSON.decoder.decode(PluginResponse.self, from: data) == response)
    }

    @Test("A describe response round trips through JSON")
    func describeRoundTrip() throws {
        let descriptor = ProviderDescriptor(
            id: "mock",
            displayName: "Mock",
            description: "A provider that invents its numbers.",
            capabilities: [.automaticUsageRetrieval, .multipleQuotas],
            protocolRange: PluginProtocolConstants.hostRange
        )
        let response = PluginResponse(id: "req-1", result: .success(.describe(descriptor)))
        let data = try PluginJSON.encoder.encode(response)
        #expect(try PluginJSON.decoder.decode(PluginResponse.self, from: data) == response)
    }

    @Test("An unsolicited message with no id round trips, so the host can drop it")
    func unsolicitedRoundTrip() throws {
        let response = PluginResponse(
            id: nil,
            result: .success(.connect(ConnectResult(accountLabel: "work")))
        )
        let data = try PluginJSON.encoder.encode(response)
        let decoded = try PluginJSON.decoder.decode(PluginResponse.self, from: data)
        #expect(decoded == response)
        #expect(decoded.id == nil)
    }

    /// Forward compatibility: a plugin built against a newer contract will send
    /// fields this build has never heard of, and refusing the whole message would
    /// break the features it does share.
    @Test("Unknown fields are ignored, not rejected")
    func unknownFieldsAreIgnored() throws {
        let json = """
        {
          "id": "req-1",
          "result": {
            "kind": "success",
            "value": {
              "kind": "connect",
              "value": {"accountLabel": "work", "someFutureField": {"nested": [1, 2]}}
            }
          },
          "addedLater": true
        }
        """
        let decoded = try PluginJSON.decoder.decode(PluginResponse.self, from: Data(json.utf8))
        #expect(decoded.id == "req-1")
        #expect(decoded.result == .success(.connect(ConnectResult(accountLabel: "work"))))
    }

    @Test("An unknown result kind is refused rather than guessed at")
    func unknownResultKindIsRejected() throws {
        let json = #"{"id":"req-1","result":{"kind":"maybe","value":{}}}"#
        #expect(throws: (any Error).self) {
            try PluginJSON.decoder.decode(PluginResponse.self, from: Data(json.utf8))
        }
    }

    @Test("A result tagged one way and holding the other is refused")
    func mismatchedResultTagIsRejected() throws {
        // Says failure, carries a success payload.
        let json = #"{"id":"r","result":{"kind":"failure","value":{"kind":"connect","value":{}}}}"#
        #expect(throws: (any Error).self) {
            try PluginJSON.decoder.decode(PluginResponse.self, from: Data(json.utf8))
        }
    }

    @Test("A capability the host does not know is dropped, not fatal")
    func unknownCapabilityIsDropped() throws {
        // Bit 20 is not defined by this build.
        let json = "1048577"
        let decoded = try PluginJSON.decoder.decode(ProviderCapabilities.self, from: Data(json.utf8))
        #expect(decoded.contains(.automaticUsageRetrieval))
        #expect(!decoded.contains(.localAuthentication))
    }

    // MARK: Error codes

    /// These raw values are written into stored sync metadata and into logs, so a
    /// renumbering would silently reinterpret history.
    @Test("Error code raw values are the ones already on the wire")
    func errorCodeRawValues() {
        #expect(ProviderErrorCode.notInstalled.rawValue == 1)
        #expect(ProviderErrorCode.notPermitted.rawValue == 2)
        #expect(ProviderErrorCode.notAuthenticated.rawValue == 3)
        #expect(ProviderErrorCode.authenticationFailed.rawValue == 4)
        #expect(ProviderErrorCode.networkUnavailable.rawValue == 5)
        #expect(ProviderErrorCode.invalidResponse.rawValue == 6)
        #expect(ProviderErrorCode.nothingToReport.rawValue == 7)
        #expect(ProviderErrorCode.pluginError.rawValue == 8)
        #expect(ProviderErrorCode.providerError.rawValue == 9)
        // Added after the first nine and given a value past all of them, so a
        // stored code keeps its meaning. The count is ten: the nine original
        // codes plus the rate limit needed, which the interface folds into
        // the same wording as a plain failure of the connection.
        #expect(ProviderErrorCode.rateLimited.rawValue == 10)
        #expect(ProviderErrorCode.allCases.count == 10)
    }

    @Test("Every error code has something to say when a plugin is silent")
    func everyCodeHasADefaultMessage() {
        for code in ProviderErrorCode.allCases {
            #expect(!ProviderError.defaultMessage(for: code).isEmpty)
        }
    }

    @Test("A code the host does not know cannot be decoded into a known state")
    func unknownErrorCodeIsRejected() throws {
        let json = #"{"code":99,"message":"from the future"}"#
        #expect(throws: (any Error).self) {
            try PluginJSON.decoder.decode(ProviderError.self, from: Data(json.utf8))
        }
    }

    // MARK: Capabilities

    @Test("Capabilities survive a round trip through their raw set")
    func capabilityDescriptionRoundTrip() {
        let capabilities: ProviderCapabilities = [
            .automaticUsageRetrieval, .historicalUsage, .backgroundRefresh,
        ]
        let description = ProviderCapabilitiesDescription(capabilities)
        #expect(description.raw == capabilities)
        #expect(description.automaticUsageRetrieval)
        #expect(!description.multipleQuotas)
    }

    @Test("A descriptor round trips through JSON")
    func descriptorRoundTrip() throws {
        let descriptor = ProviderDescriptor(
            id: "mock",
            displayName: "Mock",
            description: "Invented numbers.",
            capabilities: [.localAuthentication],
            protocolRange: ProtocolRange(
                minimum: Version(major: 1, minor: 1, patch: 0),
                maximum: Version(major: 1, minor: 4, patch: 2)
            )
        )
        let data = try PluginJSON.encoder.encode(descriptor)
        #expect(try PluginJSON.decoder.decode(ProviderDescriptor.self, from: data) == descriptor)
    }
}

@Suite("Protocol discrimination")
struct ProtocolDiscriminationTests {
    /// A request payload that is not tagged by kind is the whole class of bug the
    /// tagged envelope exists to prevent. `ConnectRequest` has one optional field,
    /// so trial-decoding it against any object succeeds — which is how a
    /// `disconnect`, whose payload carries nothing at all, arrived as a `connect`.
    @Test("An empty disconnect payload does not decode as a connect")
    func emptyDisconnectIsNotAConnect() throws {
        let data = Data(
            #"{"id":"req-1","method":"disconnect","payload":{"kind":"disconnect","value":{}}}"#.utf8
        )
        let request = try PluginJSON.decoder.decode(PluginRequest.self, from: data)
        #expect(request.payload == .disconnect(DisconnectRequest()))
    }

    @Test("An empty connect payload is a connect, not a disconnect")
    func emptyConnectIsAConnect() throws {
        let data = Data(
            #"{"id":"req-1","method":"connect","payload":{"kind":"connect","value":{}}}"#.utf8
        )
        let request = try PluginJSON.decoder.decode(PluginRequest.self, from: data)
        #expect(request.payload == .connect(ConnectRequest()))
    }

    @Test("An untagged payload is refused rather than guessed at")
    func untaggedPayloadIsRefused() {
        // `{}` matches ConnectRequest under trial decoding, because every one of
        // its fields is optional. Refusing is the only answer that cannot turn a
        // disconnect into a connect, and an untagged payload is not something this
        // protocol version ever sent.
        let data = Data(#"{"id":"req-1","method":"disconnect","payload":{}}"#.utf8)
        #expect(throws: (any Error).self) {
            try PluginJSON.decoder.decode(PluginRequest.self, from: data)
        }
    }

    @Test("A connect with credentials is not decoded as a disconnect")
    func connectWithCredentialsIsDistinct() throws {
        let data = Data(
            #"{"id":"req-1","method":"connect","payload":{"kind":"connect","value":{"credentials":"secret"}}}"#.utf8
        )
        let request = try PluginJSON.decoder.decode(PluginRequest.self, from: data)
        #expect(request.payload == .connect(ConnectRequest(credentials: "secret")))
    }

    @Test("A payload tagged with an unknown method is refused rather than guessed")
    func unknownPayloadKindIsRefused() {
        let data = Data(#"{"id":"req-1","method":"connect","payload":{"kind":"evaluate"}}"#.utf8)
        #expect(throws: (any Error).self) {
            try PluginJSON.decoder.decode(PluginRequest.self, from: data)
        }
    }
}
