#!/usr/bin/env bash
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

VERBOSE=false
for arg in "$@"; do
    if [[ "$arg" == "--verbose" || "$arg" == "-v" ]]; then
        VERBOSE=true
    fi
done
# Strip --verbose / -v from args
args=()
for arg in "$@"; do
    [[ "$arg" == "--verbose" || "$arg" == "-v" ]] || args+=("$arg")
done
set -- "${args[@]+"${args[@]}"}"

path_has_dir() {
    local dir="$1"
    case ":$PATH:" in
        *":$dir:"*) return 0 ;;
        *) return 1 ;;
    esac
}

prepend_path_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    path_has_dir "$dir" || PATH="$dir:$PATH"
}

npm_user_prefix() {
    printf '%s\n' "${AI_CLI_NPM_PREFIX:-$HOME/.local}"
}

npm_user_bin() {
    printf '%s/bin\n' "$(npm_user_prefix)"
}

prepend_path_dir "$(npm_user_bin)"

ensure_managed_block_in_file() {
    local file="$1"
    local block="$2"
    local dir

    dir="$(dirname "$file")"
    mkdir -p "$dir"
    touch "$file"
    python3 - "$file" "$block" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
block = sys.argv[2]
start = "# >>> ai-cli PATH >>>"
end = "# <<< ai-cli PATH <<<"
managed = f"{start}\n{block}\n{end}\n"

content = path.read_text() if path.exists() else ""
normalized = content.rstrip("\n")

if start in content and end in content:
    prefix, remainder = content.split(start, 1)
    _, suffix = remainder.split(end, 1)
    replacement = prefix.rstrip("\n")
    if replacement:
        replacement += "\n\n"
    replacement += managed
    suffix = suffix.lstrip("\n")
    if suffix:
        replacement += "\n" + suffix
    updated = replacement
else:
    updated = normalized
    if updated:
        updated += "\n\n"
    updated += managed

if not updated.endswith("\n"):
    updated += "\n"

changed = updated != content
path.write_text(updated)
sys.exit(0 if changed else 1)
PY
}

persist_user_bin_path() {
    local bin_dir shell_name block
    local -a files=()
    local updated=false

    bin_dir="$(npm_user_bin)"
    block="export PATH=\"$bin_dir:\$PATH\""
    shell_name="$(basename "${SHELL:-}")"

    case "$shell_name" in
        bash)
            files+=("$HOME/.bashrc" "$HOME/.profile")
            ;;
        zsh)
            files+=("$HOME/.zshrc" "$HOME/.zprofile")
            ;;
        fish)
            ensure_managed_block_in_file "$HOME/.config/fish/config.fish" "fish_add_path \"$bin_dir\"" && updated=true
            ;;
    esac

    files+=("$HOME/.profile")

    local file
    for file in "${files[@]}"; do
        ensure_managed_block_in_file "$file" "$block" && updated=true
    done

    $updated
}

read_npm_package_version() {
    local package="$1"
    local prefix="${2:-}"
    local -a cmd=(npm list -g "$package" --depth=0 --json)
    if [[ -n "$prefix" ]]; then
        cmd+=(--prefix "$prefix")
    fi
    "${cmd[@]}" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('dependencies',{}).get('$package',{}).get('version',''))" 2>/dev/null || true
}

read_command_version() {
    local binary="$1"
    local output version

    if ! command -v "$binary" >/dev/null 2>&1; then
        return 1
    fi

    output=$("$binary" --version 2>/dev/null || "$binary" -v 2>/dev/null || true)
    version=$(printf '%s\n' "$output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    [[ -n "$version" ]] || return 1
    printf '%s\n' "$version"
}

npm_global_install_is_writable() {
    local prefix global_root

    prefix=$(npm config get prefix 2>/dev/null || true)
    [[ -n "$prefix" ]] || return 1

    global_root="$prefix/lib/node_modules"
    if [[ -d "$global_root" ]]; then
        [[ -w "$global_root" ]]
    else
        [[ -d "$prefix" && -w "$prefix" ]]
    fi
}

install_npm_package() {
    local display_name="$1"
    local package="$2"
    local prefix=""
    local bin_dir
    local bin_was_on_path=false
    local -a cmd=(npm install -g "${package}@latest" --no-fund)

    if ! npm_global_install_is_writable; then
        prefix=$(npm_user_prefix)
        bin_dir="$(npm_user_bin)"
        if path_has_dir "$bin_dir"; then
            bin_was_on_path=true
        fi
        mkdir -p "$prefix"
        cmd+=(--prefix "$prefix")
    fi

    if ! $VERBOSE; then
        cmd+=(--loglevel error)
    fi

    "${cmd[@]}"

    if [[ -n "$prefix" ]]; then
        prepend_path_dir "$bin_dir"
        if ! $bin_was_on_path; then
            persist_user_bin_path >/dev/null || true
            echo -e "${GREEN}  Added ${bin_dir} to your shell PATH for future sessions.${NC}"
        fi
    fi
}

check_npm_package() {
    local display_name="$1"
    local package="$2"
    local binary="$3"

    echo -e "${CYAN}==> Checking ${display_name}...${NC}"
    local current latest
    current=$(read_npm_package_version "$package")
    if [[ -z "$current" ]]; then
        current=$(read_npm_package_version "$package" "$(npm_user_prefix)")
    fi
    if [[ -z "$current" ]]; then
        current=$(read_command_version "$binary" || true)
    fi
    latest=$(npm view "$package" version 2>/dev/null || true)

    if [[ -z "$current" ]]; then
        echo -e "${YELLOW}  Not installed, installing ${latest:-latest}...${NC}"
        install_npm_package "$display_name" "$package"
    elif [[ "$current" == "$latest" ]]; then
        echo -e "${GREEN}  Already up to date (${current})${NC}"
    else
        echo -e "${YELLOW}  Updating ${current} -> ${latest:-latest}...${NC}"
        install_npm_package "$display_name" "$package"
    fi
}

check_claude() {
    echo -e "${CYAN}==> Checking Claude Code...${NC}"
    if ! command -v claude >/dev/null 2>&1; then
        local latest
        latest=$(npm view "@anthropic-ai/claude-code" version 2>/dev/null || true)
        echo -e "${YELLOW}  Not installed, installing ${latest:-latest}...${NC}"
        install_npm_package "Claude Code" "@anthropic-ai/claude-code"
        return
    fi

    if $VERBOSE; then
        claude update 2>&1 | tee /tmp/ai-claude-update.log || true
        local output
        output=$(cat /tmp/ai-claude-update.log)
    else
        local output
        output=$(claude update 2>&1 || true)
    fi
    if echo "$output" | grep -qi "already.*latest\|up to date\|no update"; then
        local ver
        ver=$(claude --version 2>/dev/null || true)
        if [[ -n "$ver" ]]; then
            echo -e "${GREEN}  Already up to date (${ver})${NC}"
        else
            echo -e "${GREEN}  Already up to date${NC}"
        fi
    elif echo "$output" | grep -qi "command not found\|not recognized\|no such file"; then
        echo -e "${YELLOW}  Not installed${NC}"
    else
        local ver
        ver=$(claude --version 2>/dev/null || true)
        if [[ -n "$ver" ]]; then
            echo -e "${YELLOW}  Updated to ${ver}${NC}"
        else
            echo -e "${YELLOW}  Updated successfully${NC}"
        fi
    fi
}

check_gh_cli() {
    echo -e "${CYAN}==> Checking GitHub CLI...${NC}"
    local current
    current=$(gh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    if [[ -z "$current" ]]; then
        echo -e "${YELLOW}  Not installed${NC}"
        return
    fi

    # Detect package manager and upgrade
    if command -v apt-get &>/dev/null; then
        local output
        if $VERBOSE; then
            output=$(sudo apt-get update 2>&1 && sudo apt-get install --only-upgrade gh 2>&1 | tee /dev/stderr) || true
        else
            output=$(sudo apt-get update -qq 2>&1 && sudo apt-get install --only-upgrade -qq gh 2>&1) || true
        fi
        local new_ver
        new_ver=$(gh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        if [[ "$current" == "$new_ver" ]]; then
            echo -e "${GREEN}  Already up to date (${current})${NC}"
        else
            echo -e "${YELLOW}  Updated ${current} -> ${new_ver}${NC}"
        fi
    elif command -v dnf &>/dev/null; then
        local output
        if $VERBOSE; then
            sudo dnf install gh --repo gh-cli -y 2>&1 | tee /dev/stderr || true
        else
            sudo dnf install gh --repo gh-cli -y -q 2>&1 >/dev/null || true
        fi
        local new_ver
        new_ver=$(gh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        if [[ "$current" == "$new_ver" ]]; then
            echo -e "${GREEN}  Already up to date (${current})${NC}"
        else
            echo -e "${YELLOW}  Updated ${current} -> ${new_ver}${NC}"
        fi
    elif command -v brew &>/dev/null; then
        if $VERBOSE; then
            brew upgrade gh 2>&1 || true
        else
            brew upgrade gh 2>&1 >/dev/null || true
        fi
        local new_ver
        new_ver=$(gh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        if [[ "$current" == "$new_ver" ]]; then
            echo -e "${GREEN}  Already up to date (${current})${NC}"
        else
            echo -e "${YELLOW}  Updated ${current} -> ${new_ver}${NC}"
        fi
    else
        echo -e "${YELLOW}  Installed (${current}) — could not detect package manager to upgrade${NC}"
    fi
}

check_gh_copilot() {
    echo -e "${CYAN}==> Checking GitHub Copilot CLI...${NC}"
    if $VERBOSE; then
        gh copilot update 2>&1 | tee /tmp/ai-copilot-update.log || true
        local output
        output=$(cat /tmp/ai-copilot-update.log)
    else
        local output
        output=$(gh copilot update 2>&1 || true)
    fi
    if echo "$output" | grep -q "No update needed"; then
        local ver
        ver=$(echo "$output" | sed -n 's/.*current version is \([^, ]*\).*/\1/p' || true)
        echo -e "${GREEN}  Already up to date (${ver})${NC}"
    elif echo "$output" | grep -qi "updated\|updating"; then
        echo -e "${YELLOW}  Updated successfully${NC}"
    else
        echo -e "${GREEN}  Already up to date${NC}"
    fi
}

render_usage_bar() {
    python3 - "$1" <<'PY'
import sys

try:
    percent = float(sys.argv[1])
except Exception:
    percent = 0.0

segments = 20
ratio = max(0.0, min(1.0, percent / 100.0))
filled = min(segments, max(0, int(round(ratio * segments))))
print("[" + "#" * filled + "-" * (segments - filled) + "]")
PY
}

print_usage_row() {
    local label="$1"
    local percent="$2"
    local reset_at="$3"
    local bar

    bar=$(render_usage_bar "$percent")
    printf '  %-24s %s %6.1f%% left' "$label" "$bar" "$percent"
    if [[ -n "$reset_at" ]]; then
        printf '  resets %s' "$reset_at"
    fi
    printf '\n'
}

print_usage_rows() {
    local output="$1"
    local empty_message="$2"

    if [[ -z "$output" ]]; then
        echo -e "${YELLOW}  ${empty_message}${NC}"
        return
    fi

    while IFS=$'\t' read -r label percent reset_at; do
        [[ -n "$label" ]] || continue
        if [[ "$label" == "__BLANK__" ]]; then
            printf '\n'
            continue
        fi
        if [[ "$label" == "__TEXT__" ]]; then
            echo -e "${YELLOW}  ${percent}${NC}"
            continue
        fi
        [[ -n "$percent" ]] || continue
        print_usage_row "$label" "$percent" "$reset_at"
    done <<< "$output"
}

usage_claude() {
    echo -e "${CYAN}==> Claude Code...${NC}"
    local output

    if ! output=$(python3 <<'PY' 2>/dev/null
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path


def fmt_reset(value):
    if not value:
        return ""
    try:
        value = value.replace("Z", "+00:00")
        reset_at = datetime.fromisoformat(value).astimezone()
        delta_seconds = max(0, int((reset_at - datetime.now(reset_at.tzinfo)).total_seconds()))
        days = delta_seconds // 86400
        hours = (delta_seconds % 86400) // 3600
        return f"{reset_at.strftime('%Y-%m-%d %H:%M')} ({days}d {hours}h)"
    except Exception:
        return value


def cache_path():
    return Path.home() / ".claude" / ".usage_cache.json"


def load_cached_payload():
    path = cache_path()
    if not path.exists():
        return None, None

    try:
        cached = json.loads(path.read_text())
        payload = cached.get("payload")
        cached_at = cached.get("cached_at")
        if isinstance(payload, dict):
            return payload, cached_at
    except Exception:
        pass

    return None, None


def save_cached_payload(payload):
    try:
        cache_path().write_text(
            json.dumps({"cached_at": datetime.now().astimezone().isoformat(), "payload": payload})
        )
    except Exception:
        pass


def rows_from_payload(payload):
    rows = []
    for key, label in (
        ("five_hour", "5h limit"),
        ("seven_day", "7d limit"),
        ("seven_day_sonnet", "7d sonnet"),
        ("seven_day_opus", "7d opus"),
    ):
        item = payload.get(key) or {}
        utilization = item.get("utilization")
        if utilization is None:
            continue
        rows.append((label, max(0.0, 100.0 - float(utilization)), fmt_reset(item.get("resets_at"))))

    extra = payload.get("extra_usage") or {}
    if extra.get("is_enabled") and extra.get("utilization") is not None:
        rows.append(("extra usage", max(0.0, 100.0 - float(extra["utilization"])), ""))

    return rows


path = Path.home() / ".claude" / ".credentials.json"
if not path.exists():
    sys.exit(1)

data = json.loads(path.read_text())
token = data.get("claudeAiOauth", {}).get("accessToken")
if not token:
    sys.exit(1)

request = urllib.request.Request(
    "https://api.anthropic.com/api/oauth/usage",
    headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "anthropic-version": "2023-06-01",
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "claude-code",
    },
)

cached_at = None
payload = None
for attempt in range(3):
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
        save_cached_payload(payload)
        break
    except urllib.error.HTTPError as exc:
        if exc.code != 429:
            raise
        if attempt < 2:
            time.sleep(1.5 * (attempt + 1))
            continue
        payload, cached_at = load_cached_payload()
        if payload is None:
            print("__TEXT__\tUsage unavailable (Claude rate limited after retries)\t")
            sys.exit(0)

rows = rows_from_payload(payload)

if not rows:
    sys.exit(1)

for label, percent, reset_at in rows:
    print(f"{label}\t{percent:.1f}\t{reset_at}")

if cached_at:
    print(f"__TEXT__\tShowing cached usage from {fmt_reset(cached_at)}\t")
PY
    ); then
        echo -e "${YELLOW}  Usage unavailable${NC}"
        return
    fi

    print_usage_rows "$output" "Usage unavailable"
}

usage_codex() {
    echo -e "${CYAN}==> Codex CLI...${NC}"
    local output

    if ! output=$(python3 <<'PY' 2>/dev/null
import json
import sys
import urllib.request
from datetime import datetime
from pathlib import Path


def fmt_reset(value):
    if not value:
        return ""
    try:
        reset_at = datetime.fromtimestamp(int(value)).astimezone()
        delta_seconds = max(0, int((reset_at - datetime.now(reset_at.tzinfo)).total_seconds()))
        days = delta_seconds // 86400
        hours = (delta_seconds % 86400) // 3600
        return f"{reset_at.strftime('%Y-%m-%d %H:%M')} ({days}d {hours}h)"
    except Exception:
        return str(value)


path = Path.home() / ".codex" / "auth.json"
if not path.exists():
    sys.exit(1)

data = json.loads(path.read_text())
tokens = data.get("tokens") or {}
token = tokens.get("access_token")
account_id = tokens.get("account_id")
if not token or not account_id:
    sys.exit(1)

request = urllib.request.Request(
    "https://chatgpt.com/backend-api/wham/usage",
    headers={
        "Authorization": f"Bearer {token}",
        "chatgpt-account-id": account_id,
        "User-Agent": "codex-cli",
    },
)

with urllib.request.urlopen(request, timeout=30) as response:
    payload = json.loads(response.read().decode("utf-8"))

rows = []
rate_limit = payload.get("rate_limit") or {}
for key, label in (("primary_window", "5h limit"), ("secondary_window", "7d limit")):
    window = rate_limit.get(key) or {}
    used = window.get("used_percent")
    if used is None:
        continue
    rows.append((label, max(0.0, 100.0 - float(used)), fmt_reset(window.get("reset_at"))))

if not rows:
    sys.exit(1)

for label, percent, reset_at in rows:
    print(f"{label}\t{percent:.1f}\t{reset_at}")
PY
    ); then
        echo -e "${YELLOW}  Usage unavailable${NC}"
        return
    fi

    print_usage_rows "$output" "Usage unavailable"
}

usage_gemini() {
    echo -e "${CYAN}==> Gemini CLI...${NC}"
    local output gemini_bin

    gemini_bin=$(python3 <<'PY' 2>/dev/null
import os
import shutil

path = shutil.which("gemini")
if path:
    print(os.path.realpath(path))
PY
    )

    if [[ -z "$gemini_bin" || ! -f "$gemini_bin" ]]; then
        echo -e "${YELLOW}  Usage unavailable${NC}"
        return
    fi

    if ! output=$(GEMINI_BIN_REALPATH="$gemini_bin" node --input-type=module <<'NODE' 2>/dev/null
import path from 'node:path';
import { pathToFileURL } from 'node:url';

function fmtReset(value) {
  if (!value) {
    return '';
  }

  try {
    const resetAt = new Date(value);
    if (Number.isNaN(resetAt.getTime())) {
      return value;
    }

    const deltaMs = Math.max(0, resetAt.getTime() - Date.now());
    const days = Math.floor(deltaMs / 86400000);
    const hours = Math.floor((deltaMs % 86400000) / 3600000);
    const pad = (n) => String(n).padStart(2, '0');
    const stamp = `${resetAt.getFullYear()}-${pad(resetAt.getMonth() + 1)}-${pad(resetAt.getDate())} ${pad(resetAt.getHours())}:${pad(resetAt.getMinutes())}`;
    return `${stamp} (${days}d ${hours}h)`;
  } catch {
    return value;
  }
}

function moduleUrl(...parts) {
  return pathToFileURL(path.join(...parts)).href;
}

const geminiBin = process.env.GEMINI_BIN_REALPATH;
if (!geminiBin) {
  process.exit(1);
}

const distDir = path.dirname(geminiBin);
const packageRoot = path.dirname(distDir);
const coreRoot = path.join(packageRoot, 'node_modules', '@google', 'gemini-cli-core', 'dist', 'src');

const [{ getOauthClient }, { setupUser }, { CodeAssistServer }, { AuthType }] = await Promise.all([
  import(moduleUrl(coreRoot, 'code_assist', 'oauth2.js')),
  import(moduleUrl(coreRoot, 'code_assist', 'setup.js')),
  import(moduleUrl(coreRoot, 'code_assist', 'server.js')),
  import(moduleUrl(coreRoot, 'core', 'contentGenerator.js')),
]);

const config = {
  getProxy() { return undefined; },
  isBrowserLaunchSuppressed() { return false; },
  getAcpMode() { return false; },
  getValidationHandler() { return undefined; },
};

const client = await getOauthClient(AuthType.LOGIN_WITH_GOOGLE, config);
const userData = await setupUser(client, config.getValidationHandler(), {});
const server = new CodeAssistServer(
  client,
  userData.projectId,
  {},
  '',
  userData.userTier,
  userData.userTierName,
  userData.paidTier,
  undefined,
);
const quota = await server.retrieveUserQuota({ project: userData.projectId });

const buckets = [...(quota.buckets || [])].sort((a, b) => (a.modelId || '').localeCompare(b.modelId || ''));
const flashRows = [];
const proRows = [];
const otherRows = [];

for (const bucket of buckets) {
  if (!bucket.modelId || bucket.remainingFraction == null) {
    continue;
  }

  const fraction = Number(bucket.remainingFraction);
  const percent = fraction <= 1 ? fraction * 100 : fraction;
  const row = [bucket.modelId, percent, fmtReset(bucket.resetTime)];

  if (bucket.modelId.includes('flash')) {
    flashRows.push(row);
  } else if (bucket.modelId.includes('pro')) {
    proRows.push(row);
  } else {
    otherRows.push(row);
  }
}

const rows = [];
if (flashRows.length) {
  rows.push(...flashRows);
}
if (flashRows.length && proRows.length) {
  rows.push(['__BLANK__', '', '']);
}
if (proRows.length) {
  rows.push(...proRows);
}
if ((flashRows.length || proRows.length) && otherRows.length) {
  rows.push(['__BLANK__', '', '']);
}
if (otherRows.length) {
  rows.push(...otherRows);
}

if (!rows.length) {
  process.exit(1);
}

for (const [label, percent, resetAt] of rows) {
  if (label === '__BLANK__') {
    console.log(`${label}\t\t`);
    continue;
  }
  console.log(`${label}\t${percent.toFixed(1)}\t${resetAt}`);
}
NODE
    ); then
        echo -e "${YELLOW}  Usage unavailable${NC}"
        return
    fi

    print_usage_rows "$output" "Usage unavailable"
}

usage_copilot() {
    echo -e "${CYAN}==> GitHub Copilot CLI...${NC}"
    local output payload

    if ! payload=$(gh api /copilot_internal/user 2>/dev/null); then
        echo -e "${YELLOW}  Usage unavailable${NC}"
        return
    fi

    if ! output=$(python3 - "$payload" <<'PY' 2>/dev/null
import json
import sys
from datetime import datetime


def fmt_reset(value):
    if not value:
        return ""
    try:
        value = value.replace("Z", "+00:00")
        reset_at = datetime.fromisoformat(value).astimezone()
        delta_seconds = max(0, int((reset_at - datetime.now(reset_at.tzinfo)).total_seconds()))
        days = delta_seconds // 86400
        hours = (delta_seconds % 86400) // 3600
        return f"{reset_at.strftime('%Y-%m-%d %H:%M')} ({days}d {hours}h)"
    except Exception:
        return value


payload = json.loads(sys.argv[1])

rows = []
for key, value in sorted((payload.get("quota_snapshots") or {}).items()):
    if not value:
        continue

    entitlement = value.get("entitlement") or value.get("entitlementRequests") or 0
    if key != "premium_interactions" and entitlement <= 0:
        continue

    percent = value.get("percent_remaining")
    if percent is None:
        percent = value.get("remainingPercentage")
        if percent is not None and float(percent) <= 1.0:
            percent = float(percent) * 100.0

    if percent is None:
        continue

    timestamp = value.get("resetDate") or payload.get("quota_reset_date_utc") or payload.get("quota_reset_date")
    rows.append((key.replace("_", " "), float(percent), fmt_reset(timestamp)))

if not rows:
    sys.exit(1)

for label, percent, reset_at in rows:
    print(f"{label}\t{percent:.1f}\t{reset_at}")
PY
    ); then
        echo -e "${YELLOW}  Usage unavailable${NC}"
        return
    fi

    print_usage_rows "$output" "Usage unavailable"
}

do_usage() {
    usage_claude
    echo ""
    usage_codex
    echo ""
    usage_gemini
    echo ""
    usage_copilot
    echo ""
    echo -e "${GREEN}Usage check complete.${NC}"
}

do_update() {
    check_claude
    echo ""
    check_gh_cli
    echo ""
    check_gh_copilot
    echo ""
    check_npm_package "Gemini CLI" "@google/gemini-cli" "gemini"
    echo ""
    check_npm_package "Codex CLI" "@openai/codex" "codex"
    echo ""
    echo -e "${GREEN}All AI tools checked.${NC}"
}

tool="${1:-}"
shift 2>/dev/null || true

case "$tool" in
    claude)  claude --dangerously-skip-permissions "$@" ;;
    codex)   codex --yolo "$@" ;;
    gemini)  gemini --yolo "$@" ;;
    copilot) gh copilot --yolo "$@" ;;
    update)  do_update ;;
    usage)   do_usage ;;
    *)
        echo "Usage: ai <tool> [extra args]"
        echo "  ai claude   -> claude --dangerously-skip-permissions"
        echo "  ai codex    -> codex --yolo"
        echo "  ai gemini   -> gemini --yolo"
        echo "  ai copilot  -> gh copilot --yolo"
        echo "  ai update   -> update all AI tools"
        echo "  ai usage    -> show remaining usage by provider"
        echo ""
        echo "Options:"
        echo "  ai update --verbose  -> show full output from all tools"
        ;;
esac
