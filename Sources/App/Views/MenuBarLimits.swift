import Core

/// Limits understood by bundled integrations; additional limits come from snapshots.
enum MenuBarLimits {
    struct KnownLimit: Identifiable {
        let id: String
        let name: String
        let shortName: String
    }

    static func known(for providerID: String) -> [KnownLimit] {
        switch providerID {
        case "claude":
            [KnownLimit(id: "five_hour", name: "5-hour session", shortName: "5h"),
             KnownLimit(id: "seven_day", name: "Weekly", shortName: "1w"),
             KnownLimit(id: "seven_day_opus", name: "Weekly Opus", shortName: "Weekly Opus"),
             KnownLimit(id: "seven_day_sonnet", name: "Weekly Sonnet", shortName: "Weekly Sonnet"),
             KnownLimit(id: "extra_usage", name: "Extra usage", shortName: "Extra usage")]
        case "codex":
            [KnownLimit(id: "primary_window", name: "Primary limit", shortName: "Primary"),
             KnownLimit(id: "secondary_window", name: "Secondary limit", shortName: "Secondary")]
        case "cursor":
            [KnownLimit(id: "plan", name: "Included plan", shortName: "Included plan"),
             KnownLimit(id: "api", name: "API / named models", shortName: "API / named models")]
        case "copilot":
            [KnownLimit(id: "premium_interactions", name: "Premium requests", shortName: "Premium requests"),
             KnownLimit(id: "chat", name: "Chat", shortName: "Chat"),
             KnownLimit(id: "completions", name: "Completions", shortName: "Completions")]
        case "antigravity":
            [KnownLimit(id: "credits", name: "AI credits", shortName: "AI credits"),
             KnownLimit(id: "plan", name: "Plan usage", shortName: "Plan usage")]
        case "jetbrains":
            [KnownLimit(id: "plan", name: "Monthly credits", shortName: "Monthly credits"),
             KnownLimit(id: "topup", name: "Top-up credits", shortName: "Top-up credits")]
        default: []
        }
    }
}
