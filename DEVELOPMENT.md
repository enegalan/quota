# Development

## Integration structure

All provider integrations under `Integrations/` must follow a similar structure so they are consistent and easy to maintain:

- Each integration is its own SwiftPM package (`Integrations/<id>/Package.swift`).
- Use the executable product name `quota-provider-<id>`.
- Keep the integration boundary intact: only depend on `PluginKit` and `ProviderSupport` from the root package; do not reach into app modules.
- Use a single executable target structure (all sources under `Sources/`, with `main.swift` serving the integration).
- Place sources under `Sources/` with clear separation (constants, token/credential handling, clients, normalisers, and the provider handler in `main.swift` or equivalent).
- Include a `logo.png` in the integration root (required for bundling).
- Add tests under `Tests/<Provider>ProviderTests/` when there is logic to verify.
- Follow the same patterns for credential resolution, error mapping, and logging as existing integrations.

When adding a new integration or modifying an existing one, keep the structure consistent across all integrations.
