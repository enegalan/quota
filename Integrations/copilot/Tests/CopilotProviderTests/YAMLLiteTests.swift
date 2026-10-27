import Testing
@testable import QuotaPluginCopilot

@Suite("GitHub CLI hosts.yml reader")
struct YAMLLiteTests {
    @Test("Reads the active user under github.com")
    func readsActiveUser() {
        let text = """
        github.com:
            git_protocol: https
            users:
                alice:
                bob:
            user: alice
        """
        #expect(YAMLLite.string(for: "user", underHost: "github.com", in: text) == "alice")
    }

    @Test("Ignores other hosts")
    func ignoresOtherHosts() {
        let text = """
        enterprise.example:
            user: other
        github.com:
            user: alice
        """
        #expect(YAMLLite.string(for: "user", underHost: "github.com", in: text) == "alice")
    }
}
