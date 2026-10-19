import Core
import Foundation
import Platform
import PluginKit

/// One provider, with everything there is to say about it.
///
/// The same idea as `QuotaPresentation`: a view is handed one complete value
/// rather than three that have to be matched up, so a page cannot show one
/// provider's account beside another provider's version, and every caption on
/// it is worded in one place.
struct ProviderDetail: Identifiable {
    /// How the app knows the provider: its name, its state, and its versions.
    let listing: ProviderListing

    /// The account it reads, when it is signed in.
    let accountLabel: String?

    /// When it last answered, and what went wrong when it did not.
    let syncCaption: String
    let failureCaption: String?

    /// The version on this machine, the one this build carries, the protocol it
    /// speaks, and how often it is asked.
    let versionCaption: String
    let protocolCaption: String?
    let refreshCaption: String?

    /// The limits it meters, as the last reading described them.
    let pools: [ProviderPool]

    var id: String {
        listing.id
    }

    var displayName: String {
        listing.displayName
    }

    var summary: String {
        listing.summary
    }

    var state: ProviderState {
        listing.state
    }
}

/// A limit a provider meters, as the last reading described it.
struct ProviderPool: Identifiable, Hashable {
    let id: String
    let name: String
    let usagePercentage: Double?
    let resetCaption: String?
}
