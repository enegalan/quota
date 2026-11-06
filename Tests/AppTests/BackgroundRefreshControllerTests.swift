import Foundation
import Testing
@testable import App

@Suite("Background refresh controller")
@MainActor
struct BackgroundRefreshControllerTests {
    @Test("Repeated starts do not postpone the timer, and stopping cancels it")
    func repeatedStartsAndStop() async throws {
        let controller = BackgroundRefreshController(interval: 0.1)
        var ticks = 0
        controller.start { ticks += 1 }
        for _ in 0 ..< 4 {
            try await Task.sleep(for: .milliseconds(30))
            controller.start { ticks += 100 }
        }
        #expect(ticks > 0 && ticks < 100)
        controller.stop()
        let stoppedAt = ticks
        try await Task.sleep(for: .milliseconds(150))
        #expect(ticks == stoppedAt)
    }
}
