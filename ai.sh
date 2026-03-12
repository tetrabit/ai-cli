#!/usr/bin/env bash
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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

check_npm_package() {
    local display_name="$1"
    local package="$2"

    echo -e "${CYAN}==> Checking ${display_name}...${NC}"
    local current latest
    current=$(npm list -g "$package" --depth=0 --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('dependencies',{}).get('$package',{}).get('version',''))" 2>/dev/null || true)
    latest=$(npm view "$package" version 2>/dev/null || true)

    if [[ -z "$current" ]]; then
        echo -e "${YELLOW}  Not installed, installing ${latest}...${NC}"
        if $VERBOSE; then
            npm install -g "${package}@latest"
        else
            npm install -g "${package}@latest" --loglevel error
        fi
    elif [[ "$current" == "$latest" ]]; then
        echo -e "${GREEN}  Already up to date (${current})${NC}"
    else
        echo -e "${YELLOW}  Updating ${current} -> ${latest}...${NC}"
        if $VERBOSE; then
            npm install -g "${package}@latest"
        else
            npm install -g "${package}@latest" --loglevel error
        fi
    fi
}

check_claude() {
    echo -e "${CYAN}==> Checking Claude Code...${NC}"
    if ! command -v claude >/dev/null 2>&1; then
        echo -e "${YELLOW}  Not installed${NC}"
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
        print_usage_row "$label" "$percent" "$reset_at"
    done <<< "$output"
}

usage_claude() {
    echo -e "${CYAN}==> Claude Code...${NC}"
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
        value = value.replace("Z", "+00:00")
        return datetime.fromisoformat(value).astimezone().strftime("%Y-%m-%d %H:%M")
    except Exception:
        return value


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
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "claude-code",
    },
)

with urllib.request.urlopen(request, timeout=30) as response:
    payload = json.loads(response.read().decode("utf-8"))

rows = []
for key, label in (("five_hour", "5h limit"), ("seven_day", "7d limit")):
    item = payload.get(key) or {}
    utilization = item.get("utilization")
    if utilization is None:
        continue
    rows.append((label, max(0.0, 100.0 - float(utilization)), fmt_reset(item.get("resets_at"))))

extra = payload.get("extra_usage") or {}
if extra.get("is_enabled") and extra.get("utilization") is not None:
    rows.append(("extra usage", max(0.0, 100.0 - float(extra["utilization"])), ""))

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
        return datetime.fromtimestamp(int(value)).astimezone().strftime("%Y-%m-%d %H:%M")
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
    local output

    if ! output=$(python3 <<'PY' 2>/dev/null
import json
import sys
import urllib.request
from datetime import datetime
from pathlib import Path


def post(url, token, body):
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def fmt_reset(value):
    if not value:
        return ""
    try:
        value = value.replace("Z", "+00:00")
        return datetime.fromisoformat(value).astimezone().strftime("%Y-%m-%d %H:%M")
    except Exception:
        return value


path = Path.home() / ".gemini" / "oauth_creds.json"
if not path.exists():
    sys.exit(1)

creds = json.loads(path.read_text())
token = creds.get("access_token")
if not token:
    sys.exit(1)

load = post(
    "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist",
    token,
    {
        "cloudaicompanionProject": None,
        "metadata": {
            "ideType": "IDE_UNSPECIFIED",
            "platform": "PLATFORM_UNSPECIFIED",
            "pluginType": "GEMINI",
        },
    },
)
project = load.get("cloudaicompanionProject")
if not project:
    sys.exit(1)

quota = post(
    "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota",
    token,
    {"project": project},
)

rows = []
for bucket in sorted(quota.get("buckets") or [], key=lambda item: item.get("modelId") or ""):
    model_id = bucket.get("modelId")
    fraction = bucket.get("remainingFraction")
    if not model_id or fraction is None:
        continue
    percent = float(fraction) * 100.0 if float(fraction) <= 1.0 else float(fraction)
    rows.append((model_id, percent, fmt_reset(bucket.get("resetTime"))))

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

usage_copilot() {
    echo -e "${CYAN}==> GitHub Copilot CLI...${NC}"
    local sdk_path
    local output

    sdk_path=$(python3 <<'PY'
from pathlib import Path

paths = sorted(Path.home().glob('.copilot/pkg/universal/*/copilot-sdk/index.js'))
print(paths[-1] if paths else "")
PY
)

    if [[ -z "$sdk_path" ]]; then
        echo -e "${YELLOW}  Usage unavailable${NC}"
        return
    fi

    if ! output=$(node --input-type=module - "$sdk_path" <<'JS' 2>/dev/null
const sdkPath = process.argv[2];
const { CopilotClient } = await import(sdkPath);

function formatReset(value) {
  if (!value) {
    return "";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return String(value);
  }

  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hour = String(date.getHours()).padStart(2, '0');
  const minute = String(date.getMinutes()).padStart(2, '0');
  return `${year}-${month}-${day} ${hour}:${minute}`;
}

const client = new CopilotClient({ autoStart: true });
try {
  await client.start();
  const quota = await client.rpc.account.getQuota();
  const snapshots = quota.quotaSnapshots || {};

  for (const [key, value] of Object.entries(snapshots)) {
    if (!value) {
      continue;
    }
    if (key !== 'premium_interactions' && (!value.entitlementRequests || value.entitlementRequests <= 0)) {
      continue;
    }

    let percent = Number(value.remainingPercentage ?? 0);
    if (percent <= 1) {
      percent *= 100;
    }

    const label = key.replace(/_/g, ' ');
    console.log(`${label}\t${percent.toFixed(1)}\t${formatReset(value.resetDate)}`);
  }
} finally {
  try {
    await client.stop();
  } catch {}
}
JS
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
    check_npm_package "Gemini CLI" "@google/gemini-cli"
    echo ""
    check_npm_package "Codex CLI" "@openai/codex"
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
