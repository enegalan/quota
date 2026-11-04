import Core
import Platform
import SwiftUI

/// The menu bar item shows each chosen quota's today's allowance and each
/// integration's selected limits.
struct MenuBarLabel: View {
    /// The presentation the label speaks for, either handed in (for tests) or
    /// read live from the model (for the status item). Holding the model here
    /// rather than resolving it in the parent is what lets the status item
    /// notice a refresh rather than waiting to be rebuilt.
    private let presentation: QuotaPresentation?
    private let model: AppModel?

    private let formatter = PercentageFormatter()
    @Environment(\.colorScheme) private var colorScheme
    private var options: MenuBarPreferences {
        model?.menuBarPreferences ?? MenuBarPreferences()
    }

    init(presentation: QuotaPresentation?) {
        self.presentation = presentation
        model = nil
    }

    init(model: AppModel) {
        presentation = nil
        self.model = model
    }

    private var resolvedPresentations: [QuotaPresentation] {
        let candidates: [QuotaPresentation] = if let model {
            if let primary = model.primaryPresentation {
                [primary] + model.presentations.filter { $0.id != primary.id }
            } else {
                model.presentations
            }
        } else {
            presentation.map { [$0] } ?? []
        }

        var seenIntegrations = Set<String>()
        return candidates.compactMap { candidate in
            let integrationID = candidate.summary.quota.providerID.rawValue
            guard !options.hiddenIntegrations.contains(integrationID),
                  seenIntegrations.insert(integrationID).inserted
            else { return nil }
            return candidate
        }
    }

    var body: some View {
        if let image = renderedLabel {
            Image(nsImage: image)
                .renderingMode(.original)
                .accessibilityLabel(resolvedPresentations.map {
                    "\($0.summary.quota.name): \(figures(for: $0))"
                }.joined(separator: ", "))
        } else {
            Text("Quota · \(PercentageFormatter.unknown)")
        }
    }

    private var renderedLabel: NSImage? {
        let renderer = ImageRenderer(content: labelContent.environment(\.colorScheme, colorScheme))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        image?.isTemplate = false
        return image
    }

    private var labelContent: some View {
        HStack(spacing: LayoutMetrics.rowSpacing) {
            if resolvedPresentations.isEmpty {
                Text("Quota · \(PercentageFormatter.unknown)")
            } else {
                ForEach(resolvedPresentations) { presentation in
                    if presentation.id != resolvedPresentations.first?.id {
                        Text("|")
                            .foregroundStyle(.secondary)
                    }
                    quotaLabel(presentation)
                }
            }
        }
        .font(.system(size: LayoutMetrics.indicatorSize))
        .monospacedDigit()
    }

    private func quotaLabel(_ presentation: QuotaPresentation) -> some View {
        let figures = figures(for: presentation)
        return HStack(spacing: LayoutMetrics.lineSpacing) {
            if options.showLogos {
                ProviderMark(
                    providerID: presentation.summary.quota.providerID.rawValue,
                    size: LayoutMetrics.indicatorSize + 7,
                    sizesNativeImage: true
                )
            } else {
                Text(integrationName(for: presentation))
            }
            if !figures.isEmpty {
                Text(figures)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(presentation.summary.quota.name): \(figures)")
    }

    private func integrationName(for presentation: QuotaPresentation) -> String {
        let integrationID = presentation.summary.quota.providerID.rawValue
        return model?.sections.listing(id: integrationID)?.displayName
            ?? presentation.summary.quota.name
    }

    private func figures(for presentation: QuotaPresentation) -> String {
        let integrationID = presentation.summary.quota.providerID.rawValue
        let buckets = presentation.summary.snapshot?.buckets ?? []
        let limits = presentation.summary.snapshot?.knownLimits ?? []
        let hidden = options.hiddenBuckets[integrationID] ?? []
        let visible = buckets.filter { !hidden.contains($0.id) }
        var labels = visible.map { bucket in
            let label = menuBarLabel(for: bucket, limits: limits)
            let name = sharesLabel(label, besides: bucket.id, among: buckets, limits: limits)
                ? bucket.displayName
                : label
            let figures = values(used: bucket.usagePercentage, remaining: 100 - bucket.usagePercentage)
            return "\(name) \(figures)"
        }
        for limit in limits where isMissing(limit, from: buckets) && shows(limit, integrationID: integrationID) {
            labels.append("\(limit.menuBarLabel) \(values(used: nil, remaining: nil))")
        }
        return (dailyLines(for: presentation) + labels).joined(separator: "  ")
    }

    /// Today's allowance for every quota of this integration the user chose.
    ///
    /// One quota keeps the bare "Today". A second quota has to be named, and
    /// so does a single quota that is not the one this integration is drawn
    /// from: the limits beside it still come from that quota, and an unnamed
    /// "Today" would be read as its plan.
    private func dailyLines(for presentation: QuotaPresentation) -> [String] {
        let integrationID = presentation.summary.quota.providerID.rawValue
        let siblings = dailySiblings(integrationID: integrationID, fallback: presentation)
        let shown = siblings.filter {
            options.showsDailyAllowance(
                quotaID: $0.id,
                integrationID: integrationID,
                plannedQuotaID: presentation.id
            )
        }
        var ordered: [QuotaPresentation] = []
        if let planned = shown.first(where: { $0.id == presentation.id }) {
            ordered.append(planned)
        }
        for quota in shown where quota.id != presentation.id {
            ordered.append(quota)
        }
        let named = ordered.count > 1 || ordered.first?.id != presentation.id
        return ordered.map { quota in
            let allowance = quota.summary.todayAllowance
            let remaining = allowance.flatMap { value in
                value.usedToday.map { max(0, value.suggested - $0) }
            }
            let figures = values(used: allowance?.usedToday, remaining: remaining)
            guard named else { return "Today \(figures)" }
            return "Today \(quota.dailyMenuTitle(among: ordered)) \(figures)"
        }
    }

    private func dailySiblings(
        integrationID: String,
        fallback: QuotaPresentation
    ) -> [QuotaPresentation] {
        let siblings = model?.presentations.filter {
            $0.summary.quota.providerID.rawValue == integrationID
        } ?? []
        return siblings.isEmpty ? [fallback] : siblings
    }

    private func isMissing(_ limit: KnownLimit, from buckets: [UsageBucket]) -> Bool {
        !buckets.contains { $0.id == limit.id }
    }

    private func shows(_ limit: KnownLimit, integrationID: String) -> Bool {
        let hidden = options.hiddenBuckets[integrationID] ?? []
        guard !hidden.contains(limit.id) else { return false }
        let chosen = options.shownUnavailableBuckets[integrationID] ?? []
        return chosen.contains(limit.id) || limit.shownWhenUnavailable
    }

    private func menuBarLabel(for bucket: UsageBucket, limits: [KnownLimit]) -> String {
        limits.first { $0.id == bucket.id }?.menuBarLabel ?? bucket.displayName
    }

    private func sharesLabel(
        _ label: String,
        besides bucketID: String,
        among buckets: [UsageBucket],
        limits: [KnownLimit]
    ) -> Bool {
        buckets.contains { bucket in
            bucket.id != bucketID && menuBarLabel(for: bucket, limits: limits) == label
        }
    }

    private func values(used: Double?, remaining: Double?) -> String {
        let usedText = used.map { formatter.preciseString($0) } ?? PercentageFormatter.unknown
        let remainingText = remaining.map { formatter.preciseString($0) } ?? PercentageFormatter.unknown
        switch options.valueMode {
        case .used: return usedText
        case .remaining: return remainingText
        case .both: return "\(usedText) / \(remainingText)"
        }
    }

    /// The label as text, for an allowance and a formatter.
    ///
    /// A static function rather than an inline string so the wording can be
    /// asserted without rendering, and so the two figures cannot be swapped in
    /// one place and not the other. Usage that cannot be established is a dash
    /// in the numerator and the plan is still shown, since a plan is known even
    /// when today's spending is not.
    ///
    /// The two figures are spaced apart rather than written as one fraction. At
    /// the size a menu bar item is drawn, `6%/8%` runs together into a single
    /// number the eye reads as a percentage, and the whole point of the label is
    /// that the two are separate claims: what was spent, and what the day planned.
    static func text(for allowance: TodayAllowance?, formatter: PercentageFormatter) -> String {
        guard let allowance else { return "Quota · \(PercentageFormatter.unknown)" }
        return "Quota · \(figures(for: allowance, formatter: formatter))"
    }

    private static func figures(for allowance: TodayAllowance?, formatter: PercentageFormatter) -> String {
        guard let allowance else { return PercentageFormatter.unknown }
        let used = allowance.usedToday.map { formatter.preciseString($0) } ?? PercentageFormatter.unknown
        return "\(used) / \(formatter.preciseString(allowance.suggested))"
    }
}
