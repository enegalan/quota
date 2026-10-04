/// Structural facts about the plugin contract, declared here so that the types
/// that depend on them contain no unnamed literals.
public enum VersionConstants {
    /// `major.minor.patch`, and nothing else — no `v` prefix, no two-component
    /// shorthand, no pre-release suffix.
    ///
    /// A version this host does not recognise is refused rather than interpreted,
    /// so a plugin cannot talk it into accepting a shape it never implements.
    public static let componentCount: Int = 3

    /// `minimum..<maximum` — two ends, and the `..<` between them.
    public static let rangeComponentCount: Int = 2
}
