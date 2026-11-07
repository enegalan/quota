import AppKit
import Foundation
import Platform

/// Runs background refreshes on a timer and suspends them under Low Power Mode.
///
/// The planner decides what is due; this type decides when to ask.
@MainActor
final class BackgroundRefreshController {
    /// How often the timer asks the planner whether anything is due.
    ///
    /// Matches the platform's minimum poll interval: the planner already knows
    /// each provider's due time, and waking that often is enough to notice
    /// without burning battery on an empty check.
    static let tickInterval: TimeInterval = RefreshConstants.minimumPollInterval

    private let interval: TimeInterval
    private weak var model: AppModel?
    private var refresh: (@MainActor () async -> Void)?
    private var timer: Timer?
    private var timerID: UUID?
    private var powerObserver: NSObjectProtocol?
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
        guard self.refresh == nil else { return }
        self.refresh = refresh
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [
                    .userInitiatedAllowingIdleSystemSleep,
                    .suddenTerminationDisabled,
                    .automaticTerminationDisabled,
                ],
                reason: "Quota background refresh"
            )
        }
        if powerObserver == nil {
            powerObserver = NotificationCenter.default.addObserver(
                forName: .NSProcessInfoPowerStateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.powerStateChanged()
                }
            }
        }
        scheduleTimerIfNeeded()
    }

    /// Cancels the timer and unregisters the power observer.
    func stop() {
        timer?.invalidate()
        timer = nil
        timerID = nil
        refresh = nil
        if let powerObserver {
            NotificationCenter.default.removeObserver(powerObserver)
            self.powerObserver = nil
        }
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    /// Whether refreshes are allowed right now.
    var isSuspended: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Stops the timer in Low Power Mode and restarts it when power returns.
    private func powerStateChanged() {
        if isSuspended {
            timer?.invalidate()
            timer = nil
            timerID = nil
            return
        }
        scheduleTimerIfNeeded()
    }

    /// A second start while the timer is live must leave the existing fire time in place.
    private func scheduleTimerIfNeeded() {
        guard timer == nil, !isSuspended, let refresh else { return }
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
}
