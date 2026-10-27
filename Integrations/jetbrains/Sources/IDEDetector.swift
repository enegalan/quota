import Foundation
import PluginKit
import ProviderSupport

/// One JetBrains IDE install that has written an AI Assistant quota cache.
struct DetectedIDE: Equatable, Sendable {
    let name: String
    let version: String
    let basePath: URL
    let quotaFileURL: URL
    let modifiedAt: Date

    var displayName: String {
        version.isEmpty ? name : "\(name) \(version)"
    }
}

/// Finding JetBrains IDE configs that carry AI Assistant quota.
enum IDEDetector {
    /// The install whose quota file was written most recently, or nil when none.
    static func latest(fileManager: FileManager = .default) throws -> DetectedIDE {
        let installs = detect(fileManager: fileManager)
        guard let latest = installs.max(by: { $0.modifiedAt < $1.modifiedAt }) else {
            throw JetBrainsProviderError.notDetected
        }
        return latest
    }

    /// Every install under the known config roots that has a quota file.
    static func detect(fileManager: FileManager = .default) -> [DetectedIDE] {
        if let override = ProcessInfo.processInfo.environment[
            JetBrainsConstants.quotaFileEnvironment
        ], !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            if let install = install(fromQuotaFile: url, fileManager: fileManager) {
                return [install]
            }
            return []
        }

        var found: [DetectedIDE] = []
        for root in configRoots(fileManager: fileManager) {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: child.path, isDirectory: &isDirectory),
                      isDirectory.boolValue,
                      let identity = identity(fromDirectoryName: child.lastPathComponent)
                else { continue }

                let quota = child
                    .appendingPathComponent(JetBrainsConstants.optionsDirectoryName)
                    .appendingPathComponent(JetBrainsConstants.quotaFileName)
                guard let install = install(
                    name: identity.name,
                    version: identity.version,
                    basePath: child,
                    quotaFileURL: quota,
                    fileManager: fileManager
                ) else { continue }
                found.append(install)
            }
        }
        return found
    }

    private static func configRoots(fileManager: FileManager) -> [URL] {
        if let override = ProcessInfo.processInfo.environment[
            JetBrainsConstants.configRootEnvironment
        ], !override.isEmpty {
            return [URL(fileURLWithPath: (override as NSString).expandingTildeInPath)]
        }
        let home = fileManager.homeDirectoryForCurrentUser
        return JetBrainsConstants.configRelativePaths.map {
            home.appendingPathComponent($0)
        }
    }

    private static func identity(fromDirectoryName name: String) -> (name: String, version: String)? {
        for entry in JetBrainsConstants.ideDirectoryPrefixes {
            guard name.hasPrefix(entry.prefix) else { continue }
            let version = String(name.dropFirst(entry.prefix.count))
            return (entry.displayName, version)
        }
        return nil
    }

    private static func install(fromQuotaFile url: URL, fileManager: FileManager) -> DetectedIDE? {
        let options = url.deletingLastPathComponent()
        let base = options.deletingLastPathComponent()
        let identity = identity(fromDirectoryName: base.lastPathComponent)
            ?? ("JetBrains IDE", "")
        return install(
            name: identity.name,
            version: identity.version,
            basePath: base,
            quotaFileURL: url,
            fileManager: fileManager
        )
    }

    private static func install(
        name: String,
        version: String,
        basePath: URL,
        quotaFileURL: URL,
        fileManager: FileManager
    ) -> DetectedIDE? {
        guard fileManager.fileExists(atPath: quotaFileURL.path) else { return nil }
        let attributes = try? fileManager.attributesOfItem(atPath: quotaFileURL.path)
        let modified = (attributes?[.modificationDate] as? Date) ?? .distantPast
        return DetectedIDE(
            name: name,
            version: version,
            basePath: basePath,
            quotaFileURL: quotaFileURL,
            modifiedAt: modified
        )
    }
}

enum JetBrainsProviderError: Error, Equatable {
    case notDetected
    case unreadableQuotaFile
    case invalidQuotaFile
    case noUsableMeter
}

extension JetBrainsProviderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notDetected:
            "No JetBrains IDE with AI Assistant quota detected."
        case .unreadableQuotaFile:
            "Could not read the JetBrains AI quota file."
        case .invalidQuotaFile:
            "JetBrains AI quota file is present but not usable."
        case .noUsableMeter:
            "JetBrains AI quota file has no meter."
        }
    }
}

extension JetBrainsProviderError: ProviderFailure {
    var providerError: ProviderError {
        switch self {
        case .notDetected:
            ProviderError(code: .notAuthenticated)
        case .unreadableQuotaFile, .invalidQuotaFile, .noUsableMeter:
            ProviderError(code: .invalidResponse)
        }
    }
}
