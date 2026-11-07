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
        let visible = candidates.compactMap { candidate -> QuotaPresentation? in
            let integrationID = candidate.summary.quota.providerID.rawValue
            guard !options.hiddenIntegrations.contains(integrationID),
                  seenIntegrations.insert(integrationID).inserted
            else { return nil }
            return candidate
        }
        // At least one integration has to answer for the menu bar. A stored
        // document can hide the only integration (from a build where that was
        // allowed), and hiding every one must not leave the item blank.
        return visible.isEmpty ? candidates.first.map { [$0] } ?? [] : visible
    }

    private var resolvedIntegrations: [MenuBarIntegration] {
        var integrations = resolvedPresentations.map { MenuBarIntegration(presentation: $0) }
        var seen = Set(integrations.map(\.integrationID))
        for integration in model?.unplannedIntegrations ?? [] where
            !options.hiddenIntegrations.contains(integration.integrationID)
            && seen.insert(integration.integrationID).inserted
        {
            integrations.append(menuBarIntegration(unplanned: integration))
        }
        if integrations.isEmpty, let integration = model?.unplannedIntegrations.first {
            integrations = [menuBarIntegration(unplanned: integration)]
        }
        let ids = PopoverOrder.arranged(
            integrations.map(\.id),
            accordingTo: options.popoverIntegrationOrder
        )
        return ids.compactMap { id in integrations.first { $0.id == id } }
    }

    private func menuBarIntegration(unplanned: UnplannedIntegration) -> MenuBarIntegration {
        let displayName = model?.sections.listing(id: unplanned.integrationID)?.displayName
            ?? unplanned.integrationID
        return MenuBarIntegration(unplanned: unplanned, displayName: displayName)
    }

    var body: some View {
        if let image = renderedLabel {
            Image(nsImage: image)
                .renderingMode(.original)
                .accessibilityLabel(resolvedIntegrations.map {
                    "\($0.name): \(figures(for: $0))"
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
            if resolvedIntegrations.isEmpty {
                Text("Quota · \(PercentageFormatter.unknown)")
            } else {
                ForEach(resolvedIntegrations) { integration in
                    if integration.id != resolvedIntegrations.first?.id {
                        Text("|")
                            .foregroundStyle(.secondary)
                    }
                    quotaLabel(integration)
                }
            }
        }
        .font(.system(size: LayoutMetrics.indicatorSize))
        .monospacedDigit()
    }

    /// One integration's mark and figures, so a separator can sit between integrations.
    private func quotaLabel(_ provider: MenuBarIntegration) -> some View {
        let figures = figures(for: provider)
        return HStack(spacing: LayoutMetrics.lineSpacing) {
            if options.showLogos {
                ProviderMark(
                    providerID: provider.integrationID,
                    size: LayoutMetrics.indicatorSize + 7,
                    sizesNativeImage: true
                )
            } else {
                Text(model?.sections.listing(id: provider.integrationID)?.displayName ?? provider.name)
            }
            if !figures.isEmpty {
                Text(figures)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.name): \(figures)")
    }

    /// Today's allowances and the visible limits, in the order the status item draws them.
    private func figures(for provider: MenuBarIntegration) -> String {
        let integrationID = provider.integrationID
        let buckets = (provider.snapshot?.buckets ?? [])
            .filter { provider.presentation != nil || $0.period.end > (model?.reference ?? Date()) }
        let limits = provider.snapshot?.knownLimits ?? []
        // Available and unavailable stay distinct so a legacy document can
        // migrate "all available minus hidden" without promoting unchosen
        // unavailable limits.
        let availableLimitIDs = buckets.map(\.id)
        let unavailableLimitIDs = limits.map(\.id).filter { id in
            !buckets.contains { $0.id == id }
        }
        let visible = buckets.filter {
            options.showsLimit(
                $0.id,
                integrationID: integrationID,
                availableLimitIDs: availableLimitIDs,
                unavailableLimitIDs: unavailableLimitIDs
            )
        }
        var labels = visible.map { bucket in
            let label = menuBarLabel(for: bucket, limits: limits)
            let name = sharesLabel(label, besides: bucket.id, among: buckets, limits: limits)
                ? bucket.displayName
                : label
            let figures = values(used: bucket.usagePercentage, remaining: 100 - bucket.usagePercentage)
            return "\(name) \(figures)"
        }
        for limit in limits where isMissing(limit, from: buckets)
            && options.showsLimit(
                limit.id,
                integrationID: integrationID,
                availableLimitIDs: availableLimitIDs,
                unavailableLimitIDs: unavailableLimitIDs
            )
        {
            labels.append("\(limit.menuBarLabel) \(values(used: nil, remaining: nil))")
        }
        let daily = provider.presentation.map { dailyLines(for: $0) } ?? []
        return (daily + labels).joined(separator: "  ")
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
            return "Today \(quota.dailyMenuTitle(among: siblings)) \(figures)"
        }
    }

    /// Every quota of this integration. With no model, the presentation the
    /// label was given is the only sibling a test can name.
    private func dailySiblings(
        integrationID: String,
        fallback: QuotaPresentation
    ) -> [QuotaPresentation] {
        let siblings = model?.presentations.filter {
            $0.summary.quota.providerID.rawValue == integrationID
        } ?? []
        return siblings.isEmpty ? [fallback] : siblings
    }

    /// A limit the integration declared that this reading did not carry.
    private func isMissing(_ limit: KnownLimit, from buckets: [UsageBucket]) -> Bool {
        !buckets.contains { $0.id == limit.id }
    }

    /// A missing limit is drawn only when the user chose it, like an available one.
    private func shows(
        _ limit: KnownLimit,
        integrationID: String,
        availableLimitIDs: [String],
        unavailableLimitIDs: [String]
    ) -> Bool {
        options.showsLimit(
            limit.id,
            integrationID: integrationID,
            availableLimitIDs: availableLimitIDs,
            unavailableLimitIDs: unavailableLimitIDs
        )
    }

    /// The short label the integration asked for, or the bucket's own name.
    private func menuBarLabel(for bucket: UsageBucket, limits: [KnownLimit]) -> String {
        limits.first { $0.id == bucket.id }?.menuBarLabel ?? bucket.displayName
    }

    /// Whether another limit would be drawn with the same short label.
    ///
    /// Two limits that share it are indistinguishable at menu-bar size, so
    /// the longer name is used instead.
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

    /// Used, remaining, or both. A figure that was not read is a dash, not zero.
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

    /// Used over the day's plan. A missing spend stays a dash rather than zero.
    private static func figures(for allowance: TodayAllowance?, formatter: PercentageFormatter) -> String {
        guard let allowance else { return PercentageFormatter.unknown }
        let used = allowance.usedToday.map { formatter.preciseString($0) } ?? PercentageFormatter.unknown
        return "\(used) / \(formatter.preciseString(allowance.suggested))"
    }
}

private struct MenuBarIntegration: Identifiable {
    let integrationID: String
    let accountLabel: String?
    let name: String
    let snapshot: UsageSnapshot?
    let presentation: QuotaPresentation?

    var id: String {
        PopoverOrder.key(integrationID: integrationID, account: accountLabel)
    }

    init(presentation: QuotaPresentation) {
        integrationID = presentation.summary.quota.providerID.rawValue
        accountLabel = presentation.accountLabel
        name = presentation.summary.quota.name
        snapshot = presentation.summary.snapshot
        self.presentation = presentation
    }

    init(unplanned: UnplannedIntegration, displayName: String) {
        integrationID = unplanned.integrationID
        accountLabel = unplanned.accountLabel
        name = displayName
        snapshot = unplanned.snapshot
        presentation = nil
    }
}
