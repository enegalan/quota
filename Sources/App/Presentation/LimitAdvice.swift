/// What the interface says about the quotas a provider's limits need.
///
/// A provider that meters several limits is one quota per limit. Said from one
/// place because the creation flow and the provider's page both make the same
/// recommendation, and two copies of the sentence would eventually disagree
/// about the same provider.
enum LimitAdvice {
    /// The caption for a provider metering `total` limits, `taken` of which
    /// already have a quota.
    ///
    /// - Returns: nil when the provider meters one limit or none, where there is
    ///   nothing to choose between and a recommendation would be noise.
    static func caption(total: Int, taken: Int) -> String? {
        guard total > 1 else { return nil }
        if taken >= total {
            return "Every limit this provider meters already has a quota."
        }
        if taken == 0 {
            return "This provider meters \(total) limits. Create one quota per limit you want to track."
        }
        return "\(total - taken) of \(total) limits still need a quota. Create one per limit you want to track."
    }
}
