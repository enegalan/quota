import AppKit
import Foundation
import Platform

/// Runs background refreshes on a timer and suspends them under Low Power Mode.
///
/// The planner decides *what* is due; this type decides *when* to ask.
@MainActor
final class BackgroundRefreshController {
    /// How often the timer asks the planner whether anything is due.
    ///
    /// Matches the platform's minimum poll interval: the planner already knows
    /// each provider's due time, and waking that often is enough to notice
    /// without burning battery on an empty check.
    static let tickInterval: TimeInterval = RefreshConstants.minimumPollInterval

    private weak var model: AppModel?
    private var timer: Timer?
    private var powerObserver: NSObjectProtocol?

    /// Begins polling for due quotas, and watches for power-state changes.
    ///
    /// The power observer is registered before the first tick, so a machine
    /// already in Low Power Mode at launch has never scheduled anything at
    /// all. The alternative is one timer firing in the gap and doing the very
    /// work the mode is meant to prevent.
    func start(model: AppModel) {
        self.model = model
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reschedule()
            }
        }
        reschedule()
    }

    /// Cancels the timer and unregisters the power observer.
    ///
    /// Both are released rather than merely paused. The observer is a block
    /// the notification centre holds strongly, so leaving it registered would
    /// keep this controller — and through its timer, the refresh loop — alive
    /// for the life of a process that has stopped doing work.
    func stop() {
        timer?.invalidate()
        timer = nil
        if let powerObserver {
            NotificationCenter.default.removeObserver(powerObserver)
            self.powerObserver = nil
        }
    }

    /// Whether refreshes are allowed right now.
    var isSuspended: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Replaces the timer with one that reflects the current power state.
    ///
    /// Called from both directions — the first tick and every power-state
    /// change — because cancelling and rescheduling is also what makes
    /// *leaving* Low Power Mode resume refreshes. The model is held weakly,
    /// so a tick that fires after the window closes refreshes nothing rather
    /// than reviving a model the app has let go of.
    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard !isSuspended else { return }
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.tickInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.model?.refreshDue()
            }
        }
    }
}
