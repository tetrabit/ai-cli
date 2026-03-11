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
    *)
        echo "Usage: ai <tool> [extra args]"
        echo "  ai claude   -> claude --dangerously-skip-permissions"
        echo "  ai codex    -> codex --yolo"
        echo "  ai gemini   -> gemini --yolo"
        echo "  ai copilot  -> gh copilot --yolo"
        echo "  ai update   -> update all AI tools"
        echo ""
        echo "Options:"
        echo "  ai update --verbose  -> show full output from all tools"
        ;;
esac
