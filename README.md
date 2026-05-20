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
curl -fsSL https://raw.githubusercontent.com/tetrabit/ai-cli/refs/heads/main/install.sh | bash
```

From a local checkout, `./install.sh` installs the local `ai.sh`/`ai.ps1` next to it. Use `./install.sh --remote` to force downloading the latest `main` version instead.

**Windows (Git Bash / MSYS2):**

```bash
curl -fsSL https://raw.githubusercontent.com/tetrabit/ai-cli/refs/heads/main/install.sh | bash
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
| Pi Coding Agent | `ai pi` | `pi` |
| Hermes Agent | `ai hermes` | `hermes --yolo` |

All extra arguments are forwarded to the underlying tool.

## Update All Tools

```
ai update
ai update --verbose    # show full output from all tools
```

Checks each tool for updates before installing. If Gemini CLI, Codex CLI, Pi Coding Agent, or Hermes Agent are missing, `ai update` installs them first. Gemini, Codex, and Pi use npm; Hermes uses the official Hermes installer. When npm falls back to `~/.local`, `ai update` also adds `~/.local/bin` to your shell PATH for future sessions.

`ai update` also installs or updates the Pi vs Claude Code harness from `https://github.com/disler/pi-vs-claude-code`. The checkout lives at `${XDG_DATA_HOME:-~/.local/share}/ai-cli/pi-vs-claude-code` on Linux/macOS, `%LOCALAPPDATA%\ai-cli\pi-vs-claude-code` on Windows, or `AI_CLI_PI_VS_CLAUDE_CODE_DIR` when set. Bun is required to install its dependencies, and `just` is required to use the bundled recipes.

| Tool | Windows | Linux | macOS |
|------|---------|-------|-------|
| Claude Code | `winget upgrade` | `npm install` when missing, otherwise `claude update` | `npm install` when missing, otherwise `claude update` |
| GitHub CLI | `winget upgrade` | `apt` / `dnf` | `brew upgrade gh` |
| GitHub Copilot CLI | `gh copilot update` | `gh copilot update` | `gh copilot update` |
| Gemini CLI | npm version check | npm version check | npm version check |
| Codex CLI | npm version check | npm version check | npm version check |
| Pi Coding Agent | npm version check | npm version check | npm version check |
| Pi vs Claude Code | git clone/pull + `bun install` | git clone/pull + `bun install` | git clone/pull + `bun install` |
| Hermes Agent | official installer when missing, otherwise `hermes update` | official installer when missing, otherwise `hermes update` | official installer when missing, otherwise `hermes update` |

## Choose Which Tools Are Checked

Run setup to choose which tools are installed or updated by default:

```bash
ai setup
```

Setup writes a small config file at `${XDG_CONFIG_HOME:-~/.config}/ai-cli/config` (or `AI_CLI_CONFIG` if set). If no config exists, ai-cli keeps the original behavior and checks every supported tool.

`ai setup` controls:

- which tools are installed or updated during `ai update`
- which providers run during `ai usage`

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

==> Checking Pi Coding Agent...
  Already up to date (0.75.4)

==> Checking Pi vs Claude Code...
  Repo already up to date (a1b2c3d)
  Dependencies installed. Run recipes from ~/.local/share/ai-cli/pi-vs-claude-code with 'just'.

All AI tools checked.
```

## Check Remaining Usage

```bash
ai usage
```

Shows remaining usage as percentage bars for the selected supported providers in `ai.sh`:

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

- **Windows:** [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/), [Node.js](https://nodejs.org/), [GitHub CLI](https://cli.github.com/), [Bun](https://bun.sh/) and [just](https://just.systems/) for Pi vs Claude Code
- **Linux:** [Node.js](https://nodejs.org/), [GitHub CLI](https://cli.github.com/), [Bun](https://bun.sh/) and [just](https://just.systems/) for Pi vs Claude Code
- **macOS:** [Homebrew](https://brew.sh/), [Node.js](https://nodejs.org/), [GitHub CLI](https://cli.github.com/), [Bun](https://bun.sh/) and [just](https://just.systems/) for Pi vs Claude Code
