import Core
import Foundation

/// Tells the app when to read a provider again, and for what reason.
///
/// The reasons are kept rather than collapsed into one flag because they are not
/// the same decision. A popover opening wants a read now whatever the schedule
/// says, because the user is looking at the numbers. Connectivity returning wants
/// one because the reason the last read failed has just gone away. A timer wants
/// one only if enough time has passed. Anything that folds these together either
/// skips a read the user is waiting for or polls on a schedule the provider has
/// asked the app not to use.
public enum RefreshTrigger: Sendable, Equatable {
    /// The app started.
    case launch
    /// The menu bar popover was opened.
    case popoverOpened
    /// Network connectivity is back.
    ///
    /// Nothing in the app watches connectivity yet, so this is a trigger the
    /// policy understands rather than one the app raises: `ConnectivityTracker`
    /// turns a value into it, and whoever supplies that value decides when.
    case connectivityRestored
    /// The scheduled time has arrived.
    case scheduleElapsed
    /// The user asked.
    case manual
}

/// Whether a read should happen now, given a trigger and what is known.
///
/// A pure function so the policy is testable at any instant, and so the same
/// answer is given whether the question is asked by a timer or by a popover.
public struct RefreshDecision: Sendable, Equatable {
    /// Whether to read now.
    public let shouldRefresh: Bool

    /// Why not, when not. Kept so a caller can explain a skip rather than just
    /// not happening, which is the difference between a user who understands the
    /// app and one who thinks it is broken.
    public let deferral: Deferral?

    public init(shouldRefresh: Bool, deferral: Deferral? = nil) {
        self.shouldRefresh = shouldRefresh
        self.deferral = deferral
    }

    /// Why a read was skipped.
    public enum Deferral: Sendable, Equatable {
        /// Not due yet; this is when it will be.
        case notDue(until: Date)
        /// A read is already under way for this provider.
        case alreadyInFlight
    }

    /// Decides whether `trigger` should cause a read now.
    ///
    /// - Parameters:
    ///   - lastAttempt: when this provider was last read, or nil if never.
    ///   - nextDue: when the schedule says to read it next, or nil if there is
    ///     no schedule yet.
    ///   - inFlight: whether a read is running right now.
    public static func decide(
        trigger: RefreshTrigger,
        lastAttempt: Date?,
        nextDue: Date?,
        inFlight: Bool,
        now: Date
    ) -> RefreshDecision {
        // Never a second concurrent read of one provider: two in flight would
        // both file a reading and the later one to finish would win regardless
        // of which was newer.
        if inFlight {
            return RefreshDecision(shouldRefresh: false, deferral: .alreadyInFlight)
        }

        // A user asking is always answered, even ahead of a schedule that says
        // the provider asked for less traffic. The user's request is one read,
        // and the schedule exists to stop the app from making many.
        switch trigger {
        case .manual, .popoverOpened, .connectivityRestored:
            return RefreshDecision(shouldRefresh: true)
        case .launch, .scheduleElapsed:
            break
        }

        // A launch with nothing recorded is a first read, not a skipped one.
        guard let nextDue else { return RefreshDecision(shouldRefresh: true) }
        guard now >= nextDue else {
            return RefreshDecision(shouldRefresh: false, deferral: .notDue(until: nextDue))
        }
        return RefreshDecision(shouldRefresh: true)
    }
}

/// Connectivity state the app is told about, as the interface needs it.
public struct ConnectivityState: Sendable, Equatable {
    public let isConnected: Bool
    /// Whether this state is a change from the one before it.
    ///
    /// A boolean the watcher can carry, so the app refreshes on the transition to
    /// connected and not on every reading of "still connected" — which would
    /// otherwise be a poll triggered by the thing that is supposed to prevent
    /// polling.
    public let justRestored: Bool

    public init(isConnected: Bool, justRestored: Bool = false) {
        self.isConnected = isConnected
        self.justRestored = justRestored
    }
}

/// Turns a stream of connectivity readings into "a refresh is worth doing".
public struct ConnectivityTracker: Sendable {
    private var previous: Bool?

    public init() {}

    /// Reads one connectivity value and says what it means.
    ///
    /// A struct with a mutating method rather than a class holding state, so the
    /// transition is a value the caller can hold, compare and test without a
    /// reference to watch.
    public mutating func observe(_ isConnected: Bool) -> ConnectivityState {
        // Nothing observed yet counts as not connected: an app launched online
        // has just regained the ability to read, and treating that as a
        // continuing state would skip the launch refresh.
        let restored = isConnected && previous != true
        previous = isConnected
        return ConnectivityState(isConnected: isConnected, justRestored: restored)
    }

    /// The reading at launch, which is a change from nothing.
    public static func initial(_ isConnected: Bool) -> ConnectivityState {
        ConnectivityState(isConnected: isConnected, justRestored: isConnected)
    }
}
