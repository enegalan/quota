import Foundation
import Testing
@testable import QuotaPluginJetBrains

@Suite("JetBrains IDE detection", .serialized)
struct IDEDetectorTests {
    @Test("Picks the most recently modified quota file")
    func prefersNewest() throws {
        clearOverrides()
        defer { clearOverrides() }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-jetbrains-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try writeQuota(
            under: root,
            ideDirectory: "WebStorm2025.1",
            modified: Date(timeIntervalSince1970: 1000)
        )
        let newer = try writeQuota(
            under: root,
            ideDirectory: "IntelliJIdea2025.3",
            modified: Date(timeIntervalSince1970: 2000)
        )

        setenv(JetBrainsConstants.configRootEnvironment, root.path, 1)

        let ide = try IDEDetector.latest()
        #expect(ide.displayName == "IntelliJ IDEA 2025.3")
        #expect(
            ide.quotaFileURL.resolvingSymlinksInPath().path
                == newer.resolvingSymlinksInPath().path
        )
    }

    @Test("Quota file override wins")
    func fileOverride() throws {
        clearOverrides()
        defer { clearOverrides() }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-jetbrains-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeQuota(
            under: root,
            ideDirectory: "PhpStorm2024.3",
            modified: Date()
        )

        setenv(JetBrainsConstants.quotaFileEnvironment, file.path, 1)

        let ide = try IDEDetector.latest()
        #expect(ide.displayName == "PhpStorm 2024.3")
    }

    private func clearOverrides() {
        unsetenv(JetBrainsConstants.quotaFileEnvironment)
        unsetenv(JetBrainsConstants.configRootEnvironment)
    }

    private func writeQuota(
        under root: URL,
        ideDirectory: String,
        modified: Date
    ) throws -> URL {
        let options = root
            .appendingPathComponent(ideDirectory)
            .appendingPathComponent("options")
        try FileManager.default.createDirectory(at: options, withIntermediateDirectories: true)
        let file = options.appendingPathComponent("AIAssistantQuotaManager2.xml")
        let xml = """
        <application>
          <component name="AIAssistantQuotaManager2">
            <option name="quotaInfo" value="{&quot;current&quot;:&quot;1&quot;,&quot;maximum&quot;:&quot;10&quot;}" />
          </component>
        </application>
        """
        try Data(xml.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        return file
    }
}
