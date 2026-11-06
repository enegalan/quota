import AppKit
import Foundation

/// Asks the planner for due quotas throughout the lifetime of the app.
@MainActor
final class BackgroundRefreshController {
    static let tickInterval: TimeInterval = 5

    private let interval: TimeInterval
    private weak var model: AppModel?
    private var timer: Timer?
    private var timerID: UUID?
    private var activity: (any NSObjectProtocol)?

    init(interval: TimeInterval = tickInterval) {
        self.interval = interval
    }

    func start(model: AppModel) {
        self.model = model
        start { [weak self] in
            await self?.model?.refreshDue()
        }
    }

    /// Starting again must not postpone the next tick when SwiftUI recreates a view.
    func start(refresh: @escaping @MainActor () async -> Void) {
        guard timer == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Quota background refresh"
        )
        let id = UUID()
        timerID = id
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard self?.timerID == id else { return }
                await refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        timerID = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
}
