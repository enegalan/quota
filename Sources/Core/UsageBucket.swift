import Foundation

/// One metered resource as a provider reports it: how much of it has been used,
/// and the window that figure is measured over.
///
/// A provider may meter several resources against one account, so a quota points
/// at a bucket by identifier rather than reading a single figure.
///
/// The period lives here rather than on the snapshot because a provider may meter
/// several resources against *different* windows, and a snapshot that carried one
/// period for all of them could only describe a provider whose limits share a
/// clock. Some do not: a short session allowance and a weekly one reset at
/// different instants, and pacing a short limit over a week — or refusing to
/// serve it hours in — is not a rounding difference, it is the wrong number.
/// One period per bucket is what lets those be two quotas rather than one
/// compromise.
public struct UsageBucket: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let displayName: String
    public let usagePercentage: Double

    /// The window this bucket's figure is measured over.
    ///
    /// Taken from the provider rather than assumed, because a billing cycle is
    /// anchored to a renewal and a pricing change can produce one shorter than a
    /// month. Required rather than defaulted: a bucket whose window is unknown
    /// cannot be paced against, and guessing one would produce a plan against
    /// days the limit does not cover.
    public let period: QuotaPeriod

    /// A human description of the limit, such as "$20 included". Informational
    /// only: it is never parsed and never used in arithmetic, because a
    /// provider's wording is not a contract and treating it as one would make
    /// the app wrong the moment the wording changes.
    public let limitDescription: String?

    /// - Throws: `QuotaDomainError.invalidPercentage` for a value outside 0...100
    ///   or a value that is not a finite number, and
    ///   `QuotaDomainError.invalidIdentifier` for an empty bucket identifier.
    public init(
        id: String,
        displayName: String,
        usagePercentage: Double,
        period: QuotaPeriod,
        limitDescription: String? = nil
    ) throws {
        guard let identifier = try? ProviderID(id) else {
            throw QuotaDomainError.invalidIdentifier(id)
        }
        guard usagePercentage.isFinite,
              UsageConstants.percentageRange.contains(usagePercentage)
        else {
            throw QuotaDomainError.invalidPercentage(usagePercentage)
        }

        self.id = identifier.rawValue
        self.displayName = displayName
        self.usagePercentage = usagePercentage
        self.period = period
        self.limitDescription = limitDescription
    }

    /// Decoding validates, so a provider or a stored file cannot introduce a
    /// figure that violates the invariant after the fact.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            displayName: container.decode(String.self, forKey: .displayName),
            usagePercentage: container.decode(Double.self, forKey: .usagePercentage),
            period: container.decode(QuotaPeriod.self, forKey: .period),
            limitDescription: container.decodeIfPresent(String.self, forKey: .limitDescription)
        )
    }
}
