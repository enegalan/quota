/// Serialises installs across every installer in the process.
///
/// A chain of tasks rather than a bare actor, because an actor that awaits
/// inside its own method is reentrant: four callers would each suspend at their
/// first `await` inside the install and then run on top of each other, which is
/// the race this is here to prevent. Each caller waits for the one before it, so
/// the critical sections queue in the order they arrived.
///
/// A gate rather than a lock, because the work inside it is async: a mutex held
/// across an `await` would have to block a cooperative thread to stay held, and
/// blocking a cooperative thread to do file I/O is the way a deadlock starts.
actor InstallationGate {
    static let shared = InstallationGate()

    private var tail: Task<Void, Never>?

    /// Runs `work` with every other caller held back until it finishes.
    ///
    /// The successor is recorded before this call suspends, and the caller
    /// waits on its own task rather than on the tail: waiting on the tail
    /// would let two callers each await a task that awaits nothing, which
    /// is the reentrancy this gate exists to remove. A failing install does
    /// not break the chain, because the tail swallows it — one provider
    /// refusing to install must not lock out every provider after it.
    func serialise<T: Sendable>(
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let previous = tail
        let handle = Task<T, Error> {
            if let previous {
                await previous.value
            }
            return try await work()
        }
        // Recorded before this method suspends, which is what makes the chain
        // rather than four tasks all waiting on nothing.
        tail = Task { _ = try? await handle.value }
        return try await handle.value
    }
}
