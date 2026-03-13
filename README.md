# ai-cli

A single `ai` command to launch and update all your AI coding assistants.

## Platform Support

| Platform | Script | Status |
|----------|--------|--------|
| Windows | `ai.ps1` | Tested |
| Linux | `ai.sh` | Tested |
| macOS | `ai.sh` | **Untested** — should work via Homebrew + npm, but has not been verified on a Mac. |

## Quick Install

**Linux / macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/tetrabit/ai-cli/main/install.sh | bash
```

**Windows (Git Bash / MSYS2):**

```bash
curl -fsSL https://raw.githubusercontent.com/tetrabit/ai-cli/main/install.sh | bash
```

**Windows (PowerShell only):**

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
ai update --verbose    # show full output from all tools
```

Checks each tool for updates before installing. If Claude Code, Gemini CLI, or Codex CLI are missing, `ai update` installs them with npm. When npm falls back to `~/.local`, `ai update` also adds `~/.local/bin` to your shell PATH for future sessions.

| Tool | Windows | Linux | macOS |
|------|---------|-------|-------|
| Claude Code | `winget upgrade` | `npm install` when missing, otherwise `claude update` | `npm install` when missing, otherwise `claude update` |
| GitHub CLI | `winget upgrade` | `apt` / `dnf` | `brew upgrade gh` |
| GitHub Copilot CLI | `gh copilot update` | `gh copilot update` | `gh copilot update` |
| Gemini CLI | npm version check | npm version check | npm version check |
| Codex CLI | npm version check | npm version check | npm version check |

Example output:

```
==> Checking Claude Code...
  Already up to date (2.1.70)

==> Checking GitHub CLI...
  Already up to date (2.87.3)

==> Checking GitHub Copilot CLI...
  Already up to date (1.0.3)

==> Checking Gemini CLI...
  Already up to date (0.32.1)

==> Checking Codex CLI...
  Already up to date (0.113.0)

All AI tools checked.
```

## Check Remaining Usage

```bash
ai usage
```

Shows remaining usage as percentage bars for the supported providers in `ai.sh`:

- Claude Code: 5-hour and 7-day limits
- Codex CLI: 5-hour and 7-day limits
- Gemini CLI: model quota buckets returned by Gemini Code Assist
- GitHub Copilot CLI: premium request quota

Example output:

```text
==> Claude Code...
  5h limit           [####################]  100.0% left
  7d limit           [--------------------]    0.0% left  resets 2026-03-15 00:00

==> Codex CLI...
  5h limit           [##############------]   68.0% left  resets 2026-03-12 16:19
  7d limit           [###########---------]   55.0% left  resets 2026-03-18 11:15

==> Gemini CLI...
  gemini-3-flash-preview [##################--]   91.9% left  resets 2026-03-12 17:51

==> GitHub Copilot CLI...
  premium interactions [############--------]   60.6% left  resets 2026-03-12 16:29
```

## Prerequisites

- **Windows:** [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/), [Node.js](https://nodejs.org/), [GitHub CLI](https://cli.github.com/)
- **Linux:** [Node.js](https://nodejs.org/), [GitHub CLI](https://cli.github.com/)
- **macOS:** [Homebrew](https://brew.sh/), [Node.js](https://nodejs.org/), [GitHub CLI](https://cli.github.com/)
