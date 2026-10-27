import Foundation

/// Named values for the JetBrains AI Assistant provider plugin.
enum JetBrainsConstants {
    static let providerID = "jetbrains"
    static let displayName = "JetBrains AI"
    static let description =
        "Plan credits per IDE and month from JetBrains AI Assistant."

    /// Quota file the IDE writes under each installation's `options/`.
    static let quotaFileName = "AIAssistantQuotaManager2.xml"
    static let optionsDirectoryName = "options"
    static let componentName = "AIAssistantQuotaManager2"
    static let quotaInfoOptionName = "quotaInfo"
    static let nextRefillOptionName = "nextRefill"

    /// Config roots where JetBrains IDEs (and Android Studio) store state.
    static let configRelativePaths = [
        "Library/Application Support/JetBrains",
        "Library/Application Support/Google",
        ".config/JetBrains",
        ".config/Google",
    ]

    /// Directory name prefixes that identify an IDE install (before the version).
    static let ideDirectoryPrefixes: [(prefix: String, displayName: String)] = [
        ("IntelliJIdea", "IntelliJ IDEA"),
        ("IdeaIC", "IntelliJ IDEA Community"),
        ("PyCharm", "PyCharm"),
        ("WebStorm", "WebStorm"),
        ("PhpStorm", "PhpStorm"),
        ("GoLand", "GoLand"),
        ("CLion", "CLion"),
        ("Rider", "Rider"),
        ("RubyMine", "RubyMine"),
        ("DataGrip", "DataGrip"),
        ("DataSpell", "DataSpell"),
        ("RustRover", "RustRover"),
        ("AndroidStudio", "Android Studio"),
        ("Aqua", "Aqua"),
        ("Fleet", "Fleet"),
    ]

    static let planBucketID = "plan"
    static let planBucketDisplayName = "Monthly credits"
    static let topUpBucketID = "topup"
    static let topUpBucketDisplayName = "Top-up credits"

    /// JetBrains stores 1 displayed credit as this many internal units.
    static let unitsPerCredit: Double = 100_000

    /// Default refill window when the XML omits a duration (30 days).
    static let defaultPeriodSeconds: TimeInterval = 30 * 24 * 60 * 60

    static let suggestedRefreshIntervalSeconds = 300.0

    // Test overrides — never log their values
    static let quotaFileEnvironment = "QUOTA_JETBRAINS_QUOTA_FILE"
    static let configRootEnvironment = "QUOTA_JETBRAINS_CONFIG_ROOT"
}
