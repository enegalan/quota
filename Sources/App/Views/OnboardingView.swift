import AppKit
import Platform
import SwiftUI

/// First launch: an offer to browse providers, and nothing installed.
///
/// Nothing is installed and nothing is connected until the user chooses. A
/// quota app that installed a provider on first run would be reaching out to a
/// service the user never asked it to, which is the one thing rules out and
/// the one thing that makes people uninstall software.
struct OnboardingView: View {
    let sections: ProviderSections
    let model: AppModel
    /// Opens the dedicated providers screen, the same place the footer
    /// reaches once quotas exist.
    let onBrowseProviders: () -> Void

    var body: some View {
        NoticeCard(
            title: "Welcome to Quota",
            message: "Connect a service to automatically track your quota usage."
        ) {
            Button("Browse Providers", action: onBrowseProviders)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
    }
}

/// Shown when the app could not open its own storage.
struct LaunchFailureView: View {
    let message: String

    var body: some View {
        NoticeCard(title: "Quota could not start", message: message)
    }
}
