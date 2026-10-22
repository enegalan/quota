import Foundation

extension AppModel {
    // MARK: - reporting a failure

    /// Puts a failure where the interface can show it, and reloads.
    ///
    /// Every provider action ends here so that a failure has exactly one way of
    /// reaching the user: a caption on the row that failed, not a silently
    /// unchanged list that leaves the button looking as though it had worked.
    ///
    /// The failure is put up after the reload rather than before it, because the
    /// reload clears whatever error was on screen — and an action that failed
    /// with the reason in the banner and then a reload that wiped it is an
    /// action that failed with no reason at all.
    func perform(_ action: @escaping @Sendable () async throws -> Void) async {
        var failure: Error?
        do {
            try await action()
        } catch {
            failure = error
        }
        await load()
        lastError = failure?.localizedDescription
    }

    /// `perform`, for an action that has a provider busy while it runs.
    ///
    /// The flag is what disables that provider's buttons, and it was set and
    /// cleared by hand at each of the four places an action touches a provider.
    /// Set without the matching clear — an early return, a thrown error — leaves
    /// a provider permanently unclickable, and the app says the install failed
    /// rather than that it is still running.
    func performing(
        for providerID: String,
        _ action: @escaping @Sendable () async throws -> Void
    ) async {
        busyProviderID = providerID
        defer { busyProviderID = nil }
        await perform(action)
    }

    // Records a failure without reloading, for a caller that has its own answer
    // to give alongside it.
    //
    // The setter is private, so every way of failing goes through here or
    // through `perform`: a second place assigning `lastError` would be a second
    // place deciding what a user is told went wrong.

    func report(_ error: Error) {
        lastError = error.localizedDescription
    }
}
