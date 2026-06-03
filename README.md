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
| Google Antigravity | `ai antigravity` | `agy --dangerously-skip-permissions` |
| GitHub Copilot | `ai copilot` | `gh copilot --yolo` |
| Pi Coding Agent | `ai pi` | `pi` |
| Hermes Agent | `ai hermes` | `hermes --yolo` |
| Oh My Codex | — | managed by `ai update` and `ai doctor` |

All extra arguments are forwarded to the underlying tool.

## Update All Tools

```
ai update
ai update --verbose    # show full output from all tools
```

Checks dependencies and each selected tool before installing updates. Missing dependencies are installed first when ai-cli knows how to install them for the current platform, including Bun for Pi vs Claude Code. If Antigravity CLI, Codex CLI, Pi Coding Agent, Hermes Agent, or Oh My Codex are missing, `ai update` installs them first. Codex, Pi, and Oh My Codex use npm; Antigravity uses the official Antigravity installer; Hermes uses the official Hermes installer. For npm tools, `ai update` prefers your configured user npm prefix when it lives under your home directory (for example `~/.npm-global`) and otherwise falls back to `~/.local`. It moves that prefix's `bin` directory to the front of the current update session, keeps the ai-cli managed shell PATH block pointed at the chosen prefix, and removes duplicate user-prefix installs of the same package that could shadow the upgraded binary.

`ai update` also installs or updates the Pi vs Claude Code harness from `https://github.com/disler/pi-vs-claude-code`. The checkout lives at `${XDG_DATA_HOME:-~/.local/share}/ai-cli/pi-vs-claude-code` on Linux/macOS, `%LOCALAPPDATA%\ai-cli\pi-vs-claude-code` on Windows, or `AI_CLI_PI_VS_CLAUDE_CODE_DIR` when set. Bun is required to install its dependencies, and `just` is required to use the bundled recipes.

## Repair Install Issues

```bash
ai doctor
```

Checks for common install breakage and fixes what it can. On Linux/macOS, `ai doctor` replaces a stale `ai` launcher on PATH with the script currently running, prompting for `sudo` when that launcher is in a protected location such as `/usr/local/bin`. From a local checkout, run `./ai.sh doctor` once if the installed `ai` command is too old to know about `doctor`. It also checks missing dependencies, removes known legacy npm package handoffs (such as the old Pi Coding Agent package), and runs `omx doctor` to verify the Oh My Codex installation.

| Tool | Windows | Linux | macOS |
|------|---------|-------|-------|
| Claude Code | `winget upgrade` | `npm install` when missing, otherwise `claude update` | `npm install` when missing, otherwise `claude update` |
| GitHub CLI | `winget upgrade` | `apt` / `dnf` | `brew upgrade gh` |
| GitHub Copilot CLI | `gh copilot update` | `gh copilot update` | `gh copilot update` |
| Antigravity CLI | official installer | official installer | official installer |
| Codex CLI | npm version check | npm version check | npm version check |
| Pi Coding Agent | npm version check | npm version check | npm version check |
| Pi vs Claude Code | git clone/pull + `bun install` | git clone/pull + `bun install` | git clone/pull + `bun install` |
| Hermes Agent | official installer when missing, otherwise `hermes update` | official installer when missing, otherwise `hermes update` | official installer when missing, otherwise `hermes update` |
| Oh My Codex | npm version check + `omx doctor` | npm version check + `omx doctor` | npm version check + `omx doctor` |

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

==> Checking Antigravity CLI...
  Already up to date (1.0.0)

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

Shows remaining usage as percentage bars or instruction guidelines for the selected supported providers in `ai.sh` and `ai.ps1`:

- **Claude Code:** 5-hour and 7-day limits (Linux/macOS)
- **Codex CLI:** 5-hour and 7-day limits (Linux/macOS)
- **Antigravity CLI:** Antigravity-backed quota on Linux when the Antigravity keyring item is available, with an `agy /quota` log fallback for exhausted/reset status. It does not read Gemini CLI credential files or scrape OAuth tokens from npm bundles.
- **GitHub Copilot CLI:** Premium request quota (Linux/macOS)

Example output:

```text
==> Claude Code...
  5h limit           [####################]  100.0% left
  7d limit           [--------------------]    0.0% left  resets 2026-03-15 00:00

==> Codex CLI...
  5h limit           [##############------]   68.0% left  resets 2026-03-12 16:19
  7d limit           [###########---------]   55.0% left  resets 2026-03-18 11:15

==> Antigravity CLI...
  Gemini 3.5 Flash (High) [###################-]   93.8% left  resets 2026-06-04 18:08
  Gemini 3.5 Flash (Medium) [####################]   98.1% left  resets 2026-06-04 18:08

==> GitHub Copilot CLI...
  premium interactions [############--------]   60.6% left  resets 2026-03-12 16:29
```

## Development Workflow

Implementation tasks must be handed off with `td handoff <issue-id>` and then submitted with `td review <issue-id>`. Approval must come from a separate reviewer outside the implementing session.

For Antigravity usage regressions, run:

```bash
bash -n tests/antigravity-no-gemini-regression.sh
./tests/antigravity-no-gemini-regression.sh
```

## Prerequisites

- **Windows:** [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/) is used to install missing dependencies.
- **Linux:** `apt`, `dnf`, or `pacman` is used to install missing system dependencies; Bun is installed with the [official Bun installer](https://bun.com/docs/installation).
- **macOS:** [Homebrew](https://brew.sh/) is used to install missing system dependencies; Bun is installed with the [official Bun installer](https://bun.com/docs/installation).
