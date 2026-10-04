import Core
import Foundation
import Platform

/// Prints local Quota state for support, without any credential or token.
///
/// A dump that echoed a Keychain value would be a security failure
/// so this type never opens the Keychain and never asks a plugin for one.
enum DiagnosticDump {
    /// Renders everything support would ask for, as one block of text.
    ///
    /// Every repository is read through `try?` and falls back to an empty
    /// result, so a dump can be produced for the store that is the reason
    /// support was contacted. A dump that failed for the very fault it was
    /// meant to explain is the one thing this must never be.
    ///
    /// Identifiers and counts are printed and secrets are not, and the
    /// omission is stated rather than left implicit — so their absence reads
    /// as a decision instead of an oversight.
    static func render(environment: AppEnvironment) async -> String {
        var lines: [String] = []
        lines.append("Quota diagnostic dump")
        lines.append("generatedAt=\(ISO8601DateFormatter().string(from: environment.now()))")

        let preferences = await (try? environment.preferences.load()) ?? .default
        lines.append(
            "refreshIntervalSeconds=\(Int(preferences.refreshIntervalSeconds))"
        )
        lines.append(
            "disabledProviders=\(preferences.disabledProviders.sorted().joined(separator: ","))"
        )

        let quotas = await (try? environment.quotas.all()) ?? []
        lines.append("quotaCount=\(quotas.count)")
        for quota in quotas {
            lines.append(
                "quota id=\(quota.id.uuidString) name=\(quota.name) "
                    + "provider=\(quota.providerID.rawValue) bucket=\(quota.bucketID ?? "-")"
            )
        }

        let providers = await (try? environment.providers.all()) ?? []
        lines.append("providerRecordCount=\(providers.count)")
        for record in providers {
            let failure = record.lastFailure.map { "\($0.code)" } ?? "-"
            lines.append(
                "provider id=\(record.providerID.rawValue) account=\(record.authenticatedAccountLabel ?? "-") "
                    + "lastSync=\(record.lastSyncAt.map { ISO8601DateFormatter().string(from: $0) } ?? "-") "
                    + "lastFailure=\(failure) failures=\(record.consecutiveFailures)"
            )
        }

        let installed = await (try? environment.installed.all()) ?? []
        lines.append("installedCount=\(installed.count)")
        for item in installed {
            lines.append(
                "installed id=\(item.id) version=\(item.version.description) state=\(item.state.rawValue)"
            )
        }

        lines.append("secrets=omitted")
        return lines.joined(separator: "\n")
    }
}
