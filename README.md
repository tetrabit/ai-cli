# ai-cli

A single `ai` command to launch and update all your AI coding assistants.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/tetrabit/ai-cli/main/install.sh | bash
```

On Windows (PowerShell only):

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tetrabit/ai-cli/main/ai.ps1" -OutFile "C:\tools\ai.ps1"
```

## Supported Tools

| Tool | Launch Command | What it runs |
|------|---------------|--------------|
| Claude Code | `ai claude` | `claude --dangerously-skip-permissions` |
| OpenAI Codex | `ai codex` | `codex --yolo` |
| Google Gemini | `ai gemini` | `gemini --yolo` |
| GitHub Copilot | `ai copilot` | `gh copilot --yolo` |

All extra arguments are forwarded to the underlying tool.

## Update All Tools

```
ai update
```

Checks each tool for updates before installing — npm packages are skipped if already at the latest version.

| Tool | Windows | Linux / macOS |
|------|---------|---------------|
| Claude Code | `winget upgrade` | `claude update` |
| GitHub CLI | `winget upgrade` | — |
| GitHub Copilot CLI | `gh copilot update` | `gh copilot update` |
| Gemini CLI | npm version check | npm version check |
| Codex CLI | npm version check | npm version check |
| OpenCode | npm version check | npm version check |

Example output:

```
==> Checking Claude Code...
  Already up to date (2.1.70)

==> Checking GitHub Copilot CLI...
  Already up to date (1.0.3)

==> Checking Gemini CLI...
  Already up to date (0.32.1)

==> Checking Codex CLI...
  Already up to date (0.113.0)

==> Checking OpenCode...
  Already up to date (1.2.24)

All AI tools checked.
```

## Prerequisites

- **Windows:** [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/), [Node.js](https://nodejs.org/), [GitHub CLI](https://cli.github.com/)
- **Linux / macOS:** [Node.js](https://nodejs.org/), [GitHub CLI](https://cli.github.com/)
