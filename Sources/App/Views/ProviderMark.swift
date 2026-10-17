import SwiftUI

/// A provider's own mark, or the generic provider symbol when it has none.
///
/// The two views that name a provider draw one through here so they cannot
/// disagree about what a provider looks like or about the size of the column its
/// mark takes. The image is the build's; the symbol is what an identifier with no
/// image falls back to, which is what keeps a provider added without a mark
/// visible rather than blank.
struct ProviderMark: View {
    /// The identifier the mark is filed under.
    let providerID: String

    /// The side the mark is drawn at.
    var size: CGFloat = LayoutMetrics.bodySize

    /// The colour the fallback symbol takes, so a row can still say with it what
    /// the image cannot.
    var fallbackColor: Color = .accentColor

    var body: some View {
        mark
            .frame(width: size + LayoutMetrics.unit)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        if let image = ProviderLogo.image(for: providerID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: size))
                .foregroundStyle(fallbackColor)
        }
    }
}
