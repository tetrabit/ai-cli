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
    if echo "$output" | grep -qP "No update needed.*current version is \K[^\s,]+" 2>/dev/null; then
        local ver
        ver=$(echo "$output" | grep -oP "current version is \K[^\s,]+" || true)
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
    check_gh_copilot
    echo ""
    check_npm_package "Gemini CLI" "@google/gemini-cli"
    echo ""
    check_npm_package "Codex CLI" "@openai/codex"
    echo ""
    check_npm_package "OpenCode" "opencode-ai"
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
