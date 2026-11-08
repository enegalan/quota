import Foundation

/// Serialises overlapping settings preference reloads.
///
/// The settings form reloads when `AppModel.loadGeneration` moves. Two reloads
/// can be in flight at once; only the newest may apply, and a superseded
/// reload must not mark the form ready while a newer one is still running.
/// A user edit during the current reload still marks ready so the controls
/// stay interactive without applying the stale fetch.
struct SettingsReloadCoordinator: Equatable, Sendable {
    private(set) var isReady = false
    private(set) var epoch = 0
    private(set) var serial = 0

    /// Invalidates in-flight reloads after a control write.
    mutating func noteUserEdit() {
        epoch += 1
    }

    /// Starts a reload. The returned ticket is what `finish` matches against.
    mutating func begin() -> Ticket {
        serial += 1
        return Ticket(serial: serial, epoch: epoch)
    }

    /// Ends a reload started with `begin`.
    ///
    /// - `.ignore`: a newer reload owns readiness; leave `isReady` alone.
    /// - `.discard`: this reload is current but a user edit beat it; mark ready.
    /// - `.apply`: this reload may write fetched values and mark ready.
    mutating func finish(_ ticket: Ticket) -> Finish {
        guard ticket.serial == serial else { return .ignore }
        if ticket.epoch != epoch {
            isReady = true
            return .discard
        }
        isReady = true
        return .apply
    }

    struct Ticket: Equatable, Sendable {
        let serial: Int
        let epoch: Int
    }

    enum Finish: Equatable, Sendable {
        case apply
        case discard
        case ignore
    }
}
