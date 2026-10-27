# Supported providers

Quota works with AI coding providers: code editors, IDE assistants, and command-line tools.
For each provider Quota measures usage, works out how much remains, and spreads it across the
remaining days of the period.

Status:

- **Implemented** — already available in the app.
- **Next** — the provider under investigation now.
- **Candidate** — could be implemented; each one has to pass a discovery spike before it can be scheduled.
- **Research** — depends on a public API or a local solution that is not known to work.

## IDEs with integrated AI

| Provider               | Website                             | Status      | What Quota paces                                                   |
| ---------------------- | ----------------------------------- | ----------- | ------------------------------------------------------------------ |
| Cursor                 | https://cursor.com                  | Implemented | Plan usage, including per-action quotas if the editor exposes them |
| Antigravity            | https://antigravity.google          | Implemented | Antigravity platform AI credits and quota                          |
| GitHub Copilot         | https://github.com/features/copilot | Implemented | Premium usage, requests per model, plan limits                     |
| Windsurf               | https://windsurf.com                | Candidate   | Credits and actions consumed during flows                          |
| JetBrains AI Assistant | https://www.jetbrains.com/ai/       | Implemented | Plan credits per IDE and month                                     |
| Sourcegraph Cody       | https://sourcegraph.com/cody        | Candidate   | Usage and quotas per instance                                      |
| Supermaven             | https://supermaven.com              | Candidate   | Free/Pro plan usage                                                |
| CodeGPT                | https://codegpt.co                  | Candidate   | IDE plan quotas                                                    |
| Zed AI                 | https://zed.dev                     | Research    | Zed assistant usage and limits                                     |
| Xcode Intelligence     | https://developer.apple.com/xcode/  | Research    | Apple coding assistant usage                                       |
| Visual Studio Copilot  | https://visualstudio.microsoft.com/ | Research    | GitHub Copilot usage inside Visual Studio                          |
| Replit Agent           | https://replit.com/agent            | Research    | Replit Agent usage and credits                                     |
| Project IDX            | https://idx.google.com              | Research    | Google IDX usage and quotas                                        |
| Devin                  | https://devin.ai                    | Research    | Autonomous software engineer usage and credits                     |

## Coding command-line tools

| Provider           | Website                             | Status      | What Quota paces                              |
| ------------------ | ----------------------------------- | ----------- | --------------------------------------------- |
| Claude Code        | https://claude.com/code             | Implemented | Claude subscription or API usage while coding |
| OpenAI Codex CLI   | https://openai.com/codex            | Planned     | Codex plan usage and limits                   |
| Gemini CLI         | https://gemini.google.com           | Planned     | Gemini usage for terminal development         |
| GitHub Copilot CLI | https://github.com/features/copilot | Planned     | Copilot usage from terminal                   |
| Amazon Q Developer | https://aws.amazon.com/q/developer  | Planned     | Per-user and per-team quotas                  |
