import Platform
import SwiftUI

/// The colour a provider's state reads as.
///
/// One place, because the row in the providers list and the provider's own
/// page both say what state a provider is in, and two copies of that decision
/// are two answers to the same question — one of them would eventually be the
/// wrong colour, and a user would notice which.
extension ProviderState {
    /// Connected is the good news; failed and incompatible states get the
    /// destructive colour; everything else stays neutral so a page of installed
    /// providers does not look like a row of warnings.
    var tint: Color {
        switch self {
        case .connected, .synchronizing: .green
        case .installationFailed, .updateFailed, .authExpired, .missing, .incompatible: .red
        case .authRequired, .updateAvailable: .orange
        default: .secondary
        }
    }
}
