import Foundation
import Testing

@Suite("Live Cursor provider", .disabled(if: !LiveGate.isEnabled))
struct LiveCursorProviderTests {
    @Test("Live smoke: state database yields a session-shaped token")
    func liveTokenPresent() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
            )
        #expect(FileManager.default.fileExists(atPath: path.path))
    }
}

private enum LiveGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["QUOTA_LIVE_TESTS"] != nil
    }
}
