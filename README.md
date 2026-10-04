<img src="App/quota.icon/Assets/logo.png" alt="Quota" width="360" />

# Quota

> How much of my remaining quota can I use on each day until the end of the period?

Quota is a native macOS menu bar application with a management window for
editing. The menu bar is the primary entry: today's share and a quick look at
pacing. Providers, quotas, calendars, and custom policies live in the main
window. It reads how much of a provider's quota you have already used, knows
when the period ends, and works out how much you can use on each remaining day.
When the provider reports a new number, the plan is recalculated. You do nothing.

Quota is a **planning and pacing engine**, not a usage dashboard. A dashboard
answers "how much have I used?". Quota answers "given what I have used and how
much time is left, how much can I use each day?".

## Status

Version 1.0.0. Mock and Cursor providers are implemented. Cursor is packaged as
an unofficial provider. Releases are on the
[releases page](https://github.com/enegalan/quota/releases); see
[Installing a release](#installing-a-release), [Provider status](#provider-status)
and [CHANGELOG.md](CHANGELOG.md).

## Requirements

- macOS 14 or later
- Xcode 26.3 or later, for the Swift 6.3 toolchain
- Homebrew, for the formatting and linting tools

## Installing a release

Every `v*` tag builds `Quota.app`, verifies it, and attaches it to that tag's
[GitHub Release](https://github.com/enegalan/quota/releases) as
`Quota-<version>-arm64.zip` and `Quota-<version>-x86_64.zip`, each with a
`.sha256` beside it.

1.0.0: [arm64](https://github.com/enegalan/quota/releases/download/v1.0.0/Quota-1.0.0-arm64.zip)
· [x86_64](https://github.com/enegalan/quota/releases/download/v1.0.0/Quota-1.0.0-x86_64.zip)

1. Download the zip for your Mac, and check it against the checksum:

   ```sh
   shasum -a 256 -c Quota-<version>-arm64.zip.sha256
   ```

2. Unzip it and move `Quota.app` to `/Applications`.
3. Open it. A build that is signed ad-hoc is quarantined by Gatekeeper on first
   launch: right-click the app, choose **Open**, then **Open** again. If a
   `MACOS_SIGNING_IDENTITY` secret is configured for the release workflow, the
   bundle is signed with a Developer ID instead and this step does not apply.

To cut a release: set `CFBundleShortVersionString` in `App/Info.plist` to the
version, write the changelog section for it, commit, then push the tag:

```sh
git tag v0.2.0
git push origin v0.2.0
```

The workflow refuses a tag that disagrees with `CFBundleShortVersionString`, so a
release cannot claim a version its bundle does not carry. It can also be re-run
for an existing tag from the Actions tab without pushing a new one.

## Getting started

```sh
make bootstrap   # install swiftformat, swiftlint and prettier, once
make verify      # format check, lint, tests, plugins, bundle
make run         # build, bundle and launch
```

`make verify` is what CI runs. Run it before every commit.

### Everyday commands

| Command             | What it does                                     |
| ------------------- | ------------------------------------------------ |
| `make bootstrap`    | Installs the toolchain. Run once.                |
| `make format`       | Formats Swift and Markdown.                      |
| `make format-check` | Fails if anything is unformatted.                |
| `make lint`         | Format check and SwiftLint.                      |
| `make test`         | Runs the test suites. No network access is used. |
| `make plugins`      | Builds every provider plugin as its own package. |
| `make bundle`       | Assembles and signs `Quota.app`.                 |
| `make run`          | Builds, bundles and launches.                    |
| `make verify`       | Everything CI runs.                              |
| `make clean`        | Removes build products.                          |

## Architecture

Four layers, and a layer exists **only if it crosses a physical boundary**. There
are three such boundaries, so there are three layers plus the composition root.

```
App          interface and composition root
     │
Platform     all I/O: files, Keychain, processes, installation, the clock
     │
Core ──  PluginKit        domain model, calculation, and the
     │             │                 vocabulary shared with plugins
     └─────────────┘
       neither imports the other
```

One rule per layer:

| Layer       | Rule                                                                |
| ----------- | ------------------------------------------------------------------- |
| `Core`      | No I/O, no clock, no provider names. Pure domain.                   |
| `PluginKit` | Wire vocabulary only. No core, no platform.                         |
| `Platform`  | All I/O. Speaks to plugins; never knows a provider by name in code. |
| `App`       | Composition root and UI. Reads presentations, never repositories.   |

The governing product rule:

> **Providers know how to obtain usage. Quota knows how to plan usage. The UI knows
> how to present the plan.**

## Provider plugins

Providers are optional, independently versioned plugins. A build decides which
providers it offers by packaging them: whatever is in the bundle's `Providers`
directory is what the application offers, and it ships with none installed — the
user installs them. The application cannot read a provider's usage without a
plugin.

A provider is a separate Swift package under `Plugins/` that depends on
`PluginKit` and nothing else. It runs as a **child process** and speaks
newline-delimited JSON over standard input and output.

```
plugin process
    ↓  fetchUsage
UsageSnapshot          a normalised measurement: percentages and a period
    ↓
Core             the plan: how much per remaining day
    ↓
interface             today's allowance, upcoming days, the calendar
```

Adding a provider means adding a plugin. It does not mean changing the
allocation engine (`CursorProviderTests` / fictional-provider test prove that).

### Plugin-authoring guide

1. **Contract.** Implement `describe`, `connect`, `disconnect`, and `fetchUsage`
   against `PluginKit` (`PluginRequest` / `PluginResponse`).
2. **Wire protocol.** One JSON object per line, newline-terminated. See
   `PluginSide` and `PluginFraming`.
3. **Nine error codes** (`ProviderErrorCode`): `notInstalled`, `notPermitted`,
   `notAuthenticated`, `authenticationFailed`, `networkUnavailable`,
   `invalidResponse`, `nothingToReport`, `pluginError`, `providerError`, plus
   `rateLimited`. Branch on the code, never on the message.
4. **Capabilities.** Declare what you support with `ProviderCapabilities`
   (automatic usage, historical usage, multiple quotas).
5. **Build.** From the plugin directory:

   ```sh
   swift build --package-path Plugins/<id>
   ```

   Or `make plugins` for every package under `Plugins/`.

6. **Name.** The package must produce an executable named
   `quota-provider-<id>`, where `<id>` is the directory name under `Plugins/`.
   `Scripts/bundle.sh` packages each one as `Providers/<id>.tar.gz` inside the
   application, and that file name is the identifier everything else uses, so
   there is no separate list to keep in step. A package whose executable is
   named differently fails the bundle rather than being skipped.
7. **Worked example.** `Plugins/mock` is the scripted reference.
   `Plugins/cursor` is a real unofficial integration.

## Why the application is not sandboxed

The application is deliberately **not** sandboxed. Two requirements cannot be met
inside the App Sandbox:

1. It reads a provider application's local state, such as a SQLite store in that
   application's Application Support directory.
2. It performs outbound network requests to providers on the user's behalf.

The alternative would be App Store distribution, which is a product decision that
has not been made. The compromise is that the entitlement set is kept to the
minimum (see `App/Quota.entitlements`, TASK-356), the reasoning is recorded here,
and the read-only nature of the data Quota touches is stated per provider.

## Security

- Provider credentials are stored in the macOS Keychain and nowhere else. Never in
  a preferences file, never in a log line, never in a diagnostic dump
  (Quota → Copy Diagnostic Dump).
- Tokens belonging to a provider's own application are re-read on each refresh and
  are never copied into Quota's storage.
- The unauthorised-response body of a provider request is suppressed, because such
  a body can echo the request's own credentials back.
- Quota has no backend, no account, and no cloud storage. Usage data stays on the
  machine except for the requests Quota makes to the provider itself.

## Testing

```sh
make test
```

The core test suite never requires network access, and CI runs it with networking
disabled so a test that reaches out fails rather than passing on a developer's
machine.

Live tests against a real provider account are opt-in and marked slow:

```sh
QUOTA_LIVE_TESTS=1 swift test --filter Live
```

## Provider status

| Provider | Mechanism                       | Official | Verified   | Poll interval  | Fragility                                                                |
| -------- | ------------------------------- | -------- | ---------- | -------------- | ------------------------------------------------------------------------ |
| Mock     | Scripted, no network            | n/a      | 2026-09-26 | n/a            | none                                                                     |
| Cursor   | Local session + dashboard HTTPS | no       | 2026-09-30 | 300s (clamped) | Unofficial endpoints; SQLite token path may move; stable across 80h poll |

Spike evidence: [`spec/0004-cursor-spike-report.md`](spec/0004-cursor-spike-report.md).

## Contributing

```sh
make bootstrap
make format
make lint
make test
make verify
```

`make lint` runs format-check and SwiftLint.

Rules:

1. **A new provider must not require a change to the core or the allocation
   engine.** If it does, the design is wrong, not the engine.
2. **No numeric literal without a name.** Policy numbers live in `*Constants.swift`.
   Format properties live next to the format.
3. **Commits follow Conventional Commits** (`feat:`, `fix:`, `docs:`, …).
4. Do not claim a Definition of Done item in Appendix B without a passing test or
   an explicit checklist entry in the milestones document.
