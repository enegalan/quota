import Core
import SwiftUI

/// The limit a new quota will watch, when the provider meters more than one.
///
/// Only shown when there is a choice. A provider metering a single limit has
/// nothing to decide, and a picker over one entry is a control that cannot change
/// anything — noise in a flow whose other steps all can.
///
/// Each option carries its own window, because the two are what a user is
/// choosing between: a five-hour allowance and a weekly one are not two spellings
/// of the same quota, and "Session (resets in 3h)" beside "Weekly (6 days left)"
/// is the difference between picking a number and picking a plan.
///
/// The limits already spoken for are shown but disabled rather than hidden,
/// because a user who has a quota on the weekly limit and is offered the choice
/// again is being told the choice was not remembered; showing it struck through
/// says the opposite.
struct BucketPicker: View {
    /// Every limit the provider meters, in the order it reported them.
    let buckets: [UsageBucket]

    /// Which of them already have a quota of their own.
    let takenIDs: Set<String>

    /// The instant the windows are described relative to.
    let reference: Date
    let calendar: Calendar

    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.lineSpacing) {
            Text("Limit")
                .font(.system(size: LayoutMetrics.footnoteSize, weight: .semibold))
            Picker("", selection: $selection) {
                ForEach(buckets) { bucket in
                    Text(label(for: bucket))
                        .disabled(takenIDs.contains(bucket.id))
                        .tag(Optional(bucket.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Caption(text: advice)
        }
    }

    /// What the picker says under the menu about how many quotas this provider needs.
    ///
    /// A multi-limit provider is one quota per limit: the picker chooses which
    /// window this quota watches, and the remaining ones stay open for another
    /// pass through creation. Saying that here is what stops a user leaving with
    /// only the five-hour window and wondering where the weekly one went.
    private var advice: String {
        if buckets.allSatisfy({ takenIDs.contains($0.id) }) {
            return "Every limit this provider meters already has a quota."
        }
        let free = buckets.filter { !takenIDs.contains($0.id) }.count
        if free == buckets.count {
            return "This provider meters \(buckets.count) limits. Create one quota per limit you want to track."
        }
        return "\(free) of \(buckets.count) limits still need a quota. Create one per limit you want to track."
    }

    /// Describes one limit as the picker shows it: name, and what is left.
    private func label(for bucket: UsageBucket) -> String {
        let days = bucket.period.remainingDays(through: reference, calendar: calendar)
        let when = days == 0 ? "ending today" : "\(days)d left"
        return "\(bucket.displayName) — \(when)"
    }
}
