import Foundation

/// How old a reading may get before the interface has to say so.
///
/// Three lines, ascending, and they all live here rather than partly in the
/// scheduler: a reading cannot be "fresh" against one and "stale" against
/// another, and the exact disagreement that causes is what these numbers are
/// for. They are read by the interface's four freshness states and by nothing
/// else — how often a provider is polled is a separate decision, in
/// `RefreshConstants`.
///
/// Public because the freshness states are decided above this layer: the numbers
/// are the policy, and a copy of them in the layer that reads them is the second
/// answer this file exists to prevent.
public enum StalenessConstants {
    /// Under this, a reading is current; at or over it, it is ageing.
    ///
    /// Two polls at the default interval. A reading that has aged past the point
    /// where the *next* read was due has missed a refresh, but the one after that
    /// is usually seconds behind it — so this is a line about a read that is
    /// running late rather than one that has stopped happening, and a figure
    /// sitting on it is still a figure about today.
    public static let ageingAfter: TimeInterval = 30 * 60

    /// At or over this, a reading is stale: still shown, but flagged.
    ///
    /// Further out than the current line because a reading that is merely late
    /// deserves a caption, and one that has been wrong all day deserves a
    /// warning.
    public static let staleAfter: TimeInterval = 60 * 60

    /// Over this, a reading is not shown as a number at all.
    ///
    /// A week, because past that a figure is about the shape of the period rather
    /// than about today, and a number that precise would be a lie.
    public static let unavailableAfter: TimeInterval = 7 * 24 * 60 * 60
}
