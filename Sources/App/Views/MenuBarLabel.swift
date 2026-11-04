import Core
import Platform
import SwiftUI

/// The menu bar item shows today's allowance and the provider's selected limits.
struct MenuBarLabel: View {
    /// The presentation the label speaks for, either handed in (for tests) or
    /// read live from the model (for the status item). Holding the model here
    /// rather than resolving it in the parent is what lets the status item
    /// notice a refresh rather than waiting to be rebuilt.
    private let presentation: QuotaPresentation?
    private let model: AppModel?

    private let formatter = PercentageFormatter()
    @Environment(\.colorScheme) private var colorScheme
    private var options: MenuBarPreferences { model?.menuBarPreferences ?? MenuBarPreferences() }

    init(presentation: QuotaPresentation?) {
        self.presentation = presentation
        model = nil
    }

    init(model: AppModel) {
        presentation = nil
        self.model = model
    }

    private var resolvedPresentations: [QuotaPresentation] {
        let candidates: [QuotaPresentation]
        if let model {
            if let primary = model.primaryPresentation {
                candidates = [primary] + model.presentations.filter { $0.id != primary.id }
            } else {
                candidates = model.presentations
            }
        } else {
            candidates = presentation.map { [$0] } ?? []
        }

        var seenProviders = Set<String>()
        return candidates.compactMap { candidate in
            let providerID = candidate.summary.quota.providerID.rawValue
            guard !options.hiddenProviders.contains(providerID), seenProviders.insert(providerID).inserted else {
                return nil
            }
            guard let selected = options.selectedQuotas[providerID] else { return candidate }
            return candidates.first { $0.id == selected && $0.summary.quota.providerID.rawValue == providerID }
                ?? candidate
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
            } else if figures.isEmpty {
                Text(model?.sections.listing(id: presentation.summary.quota.providerID.rawValue)?.displayName
                    ?? presentation.summary.quota.name)
            }
            if !figures.isEmpty { Text(figures) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(presentation.summary.quota.name): \(figures)")
    }

    private func figures(for presentation: QuotaPresentation) -> String {
        let providerID = presentation.summary.quota.providerID.rawValue
        let buckets = presentation.summary.snapshot?.buckets ?? []
        let visible = buckets.filter { !(options.hiddenBuckets[providerID] ?? []).contains($0.id) }
        var labels = visible.map { bucket in
            let label = Self.windowLabel(for: bucket)
            let ambiguous = buckets.filter { Self.windowLabel(for: $0) == label }.count > 1
            let figures = values(used: bucket.usagePercentage, remaining: 100 - bucket.usagePercentage)
            return "\(ambiguous ? bucket.displayName : label) \(figures)"
        }
        for limit in MenuBarLimits.known(for: providerID) where
            !buckets.contains(where: { $0.id == limit.id })
                && (options.shownUnavailableBuckets[providerID] ?? []).contains(limit.id)
                && !(options.hiddenBuckets[providerID] ?? []).contains(limit.id) {
            labels.append("\(limit.shortName) \(values(used: nil, remaining: nil))")
        }
        var result: [String] = []
        if options.showDailyQuota && !options.hiddenDailyProviders.contains(providerID) {
            let allowance = presentation.summary.todayAllowance
            let remaining = allowance.flatMap { value in value.usedToday.map { max(0, value.suggested - $0) } }
            let daily = values(used: allowance?.usedToday, remaining: remaining)
            result.append("Today \(daily)")
        }
        return (result + labels).joined(separator: "  ")
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

    static func windowLabel(for bucket: UsageBucket) -> String {
        let hours = bucket.period.end.timeIntervalSince(bucket.period.start) / 3600
        if bucket.displayName == "5-hour session", abs(hours - 5) < 0.02 { return "5h" }
        if bucket.displayName == "Weekly", abs(hours - 168) < 0.02 { return "1w" }
        return bucket.displayName
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
