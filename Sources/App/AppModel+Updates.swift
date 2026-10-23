import AppKit
import Foundation
import Platform

extension AppModel {
    /// Whether the app checks GitHub for a newer release on its own.
    func automaticUpdateChecksEnabled() async -> Bool {
        let preferences = await (try? environment.preferences.load()) ?? .default
        return preferences.automaticUpdateChecksEnabled
    }

    /// Enables or disables automatic update checks.
    func setAutomaticUpdateChecksEnabled(_ enabled: Bool) async {
        await perform {
            let current = try await self.environment.preferences.load()
            try await self.environment.preferences.save(
                current.withAutomaticUpdateChecksEnabled(enabled)
            )
        }
    }

    /// Asks GitHub whether a newer release exists.
    ///
    /// - Parameter force: when true, skips the once-per-day throttle and the
    ///   automatic-checks preference, and opens the release page whenever a
    ///   newer version is found. When false, only runs if automatic checks are
    ///   on and the last check is older than a day, and opens the browser only
    ///   for a version that has not been announced yet.
    func checkForUpdates(force: Bool) async {
        guard !isCheckingForUpdates, let preferences = await loadPreferencesForUpdateCheck(force: force) else {
            return
        }
        let now = environment.now()
        guard force || shouldCheckAutomatically(preferences: preferences, now: now) else {
            return
        }

        isCheckingForUpdates = true
        updateStatus = .checking
        defer { isCheckingForUpdates = false }

        let outcome = await ReleaseUpdateChecker.check(
            current: BundleConstants.applicationVersion,
            fetcher: releaseFetcher
        )
        await applyUpdateOutcome(outcome, force: force, preferences: preferences, checkedAt: now)
    }

    /// Opens the release page for the update currently shown in settings.
    func openAvailableUpdate() {
        guard case .available(_, let url) = updateStatus else { return }
        openUpdateRelease(url)
    }

    /// Runs an automatic update check after the interface has loaded.
    func maybeCheckForUpdatesAutomatically() async {
        await checkForUpdates(force: false)
    }

    /// Loads preferences for an update check, or nil when the check must stop.
    ///
    /// Automatic checks bail out when the store cannot be read. A manual check
    /// continues with defaults so Check Now still asks GitHub.
    private func loadPreferencesForUpdateCheck(force: Bool) async -> Preferences? {
        do {
            return try await environment.preferences.load()
        } catch {
            report(error)
            return force ? .default : nil
        }
    }

    private func shouldCheckAutomatically(preferences: Preferences, now: Date) -> Bool {
        guard preferences.automaticUpdateChecksEnabled else { return false }
        guard let last = preferences.lastUpdateCheckAt else { return true }
        return now.timeIntervalSince(last) >= UpdateConstants.minimumCheckInterval
    }

    private func saveLastUpdateCheck(at now: Date) async {
        do {
            let current = try await environment.preferences.load()
            try await environment.preferences.save(current.withLastUpdateCheckAt(now))
        } catch {
            report(error)
        }
    }

    private func applyUpdateOutcome(
        _ outcome: UpdateCheckOutcome,
        force: Bool,
        preferences: Preferences,
        checkedAt: Date
    ) async {
        switch outcome {
        case .upToDate:
            updateStatus = .upToDate
            await saveLastUpdateCheck(at: checkedAt)
        case .available(let version, let releaseURL):
            updateStatus = .available(version: version.description, url: releaseURL)
            await saveLastUpdateCheck(at: checkedAt)
            let shouldOpen = force
                || preferences.announcedUpdateVersion != version.description
            if shouldOpen {
                openUpdateRelease(releaseURL)
                await saveAnnouncedUpdate(version.description)
            }
        case .failed(let message):
            updateStatus = .failed(message)
        }
    }

    private func saveAnnouncedUpdate(_ version: String) async {
        do {
            let current = try await environment.preferences.load()
            try await environment.preferences.save(
                current.withAnnouncedUpdateVersion(version)
            )
        } catch {
            report(error)
        }
    }

    private func openUpdateRelease(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
