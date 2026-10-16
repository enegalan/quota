# Supported providers

Quota works with AI coding providers: code editors, IDE assistants, and command-line tools.
For each provider Quota measures usage, works out how much remains, and spreads it across the
remaining days of the period.

Status:

- **Implemented** — already available in the app.
- **Planned** — next provider to implement.
- **Research** — depends on a public API or a local solution.

## IDEs with integrated AI

| Provider               | Website                             | Status      | What Quota paces                                                   |
| ---------------------- | ----------------------------------- | ----------- | ------------------------------------------------------------------ |
| Cursor                 | https://cursor.com                  | Implemented | Plan usage, including per-action quotas if the editor exposes them |
| Antigravity            | https://antigravity.google          | Research    | Antigravity platform AI credits and quota                          |
| GitHub Copilot         | https://github.com/features/copilot | Planned     | Premium usage, requests per model, plan limits                     |
| Windsurf               | https://windsurf.com                | Planned     | Credits and actions consumed during flows                          |
| JetBrains AI Assistant | https://www.jetbrains.com/ai/       | Planned     | Plan credits per IDE and month                                     |
| Sourcegraph Cody       | https://sourcegraph.com/cody        | Planned     | Usage and quotas per instance                                      |
| Supermaven             | https://supermaven.com              | Planned     | Free/Pro plan usage                                                |
| CodeGPT                | https://codegpt.co                  | Planned     | IDE plan quotas                                                    |
| Zed AI                 | https://zed.dev                     | Research    | Zed assistant usage and limits                                     |
| Xcode Intelligence     | https://developer.apple.com/xcode/  | Research    | Apple coding assistant usage                                       |
| Visual Studio Copilot  | https://visualstudio.microsoft.com/ | Research    | GitHub Copilot usage inside Visual Studio                          |
| Replit Agent           | https://replit.com/agent            | Research    | Replit Agent usage and credits                                     |
| Project IDX            | https://idx.google.com              | Research    | Google IDX usage and quotas                                        |
| Devin                  | https://devin.ai                    | Research    | Autonomous software engineer usage and credits                     |

## Coding command-line tools

| Provider           | Website                             | Status   | What Quota paces                                 |
| ------------------ | ----------------------------------- | -------- | ------------------------------------------------ |
| Claude Code        | https://claude.com/code             | Planned  | Claude subscription or API usage while coding    |
| OpenAI Codex CLI   | https://openai.com/codex            | Planned  | Codex plan usage and limits                      |
| Gemini CLI         | https://gemini.google.com           | Planned  | Gemini usage for terminal development            |
| GitHub Copilot CLI | https://github.com/features/copilot | Planned  | Copilot usage from terminal                      |
| Aider              | https://aider.chat                  | Planned  | Usage delegated to the configured model provider |
| Amazon Q Developer | https://aws.amazon.com/q/developer  | Planned  | Per-user and per-team quotas                     |
| OpenCode           | https://opencode.ai                 | Research | Usage across configured providers                |

## IDE extensions that aggregate providers

Some extensions do not have their own quota; they use OpenAI, Anthropic, or other providers instead.

| Provider  | Website              | Status   | What Quota paces                           |
| --------- | -------------------- | -------- | ------------------------------------------ |
| Continue  | https://continue.dev | Research | Usage according to the configured provider |
| Cline     | https://cline.bot    | Research | Usage according to the configured provider |
| Roo Code  | https://roocode.com  | Research | Usage according to the configured provider |
| Kilo Code | https://kilocode.ai  | Research | Usage according to the configured provider |
