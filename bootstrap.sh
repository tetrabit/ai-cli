#!/usr/bin/env bash
set -euo pipefail

# Bootstrap prerequisites for ai-cli on Debian/Ubuntu.
# Must be run as root (or via sudo).

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: this script must be run as root (sudo ./bootstrap.sh)${NC}"
    exit 1
fi

echo -e "${CYAN}==> Updating apt package index...${NC}"
apt-get update -qq

# ── Core utilities ──────────────────────────────────────────────────
echo -e "${CYAN}==> Installing core utilities (curl, git, python3)...${NC}"
apt-get install -y -qq curl git python3 ca-certificates gnupg >/dev/null
echo -e "${GREEN}  Done${NC}"

# ── Node.js (via NodeSource) ────────────────────────────────────────
echo ""
echo -e "${CYAN}==> Checking Node.js...${NC}"
if command -v node &>/dev/null; then
    NODE_VER=$(node --version 2>/dev/null || true)
    echo -e "${GREEN}  Already installed (${NODE_VER})${NC}"
else
    echo -e "${YELLOW}  Installing Node.js LTS via NodeSource...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - >/dev/null 2>&1
    apt-get install -y -qq nodejs >/dev/null
    NODE_VER=$(node --version 2>/dev/null || true)
    echo -e "${GREEN}  Installed Node.js ${NODE_VER}${NC}"
fi

# Verify npm is available
if ! command -v npm &>/dev/null; then
    echo -e "${RED}  npm not found after Node.js install — something went wrong${NC}"
    exit 1
fi
NPM_VER=$(npm --version 2>/dev/null || true)
echo -e "${GREEN}  npm ${NPM_VER}${NC}"

# ── GitHub CLI (official apt repo) ──────────────────────────────────
echo ""
echo -e "${CYAN}==> Checking GitHub CLI...${NC}"
if command -v gh &>/dev/null; then
    GH_VER=$(gh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    echo -e "${GREEN}  Already installed (${GH_VER})${NC}"
    # Ensure the official repo is present so future apt upgrades get the latest
    if [ ! -f /etc/apt/sources.list.d/github-cli.list ] && [ ! -f /usr/share/keyrings/githubcli-archive-keyring.gpg ]; then
        echo -e "${YELLOW}  Adding official GitHub CLI apt repo for future updates...${NC}"
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
        chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            > /etc/apt/sources.list.d/github-cli.list
        apt-get update -qq
    fi
else
    echo -e "${YELLOW}  Installing GitHub CLI from official repo...${NC}"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list
    apt-get update -qq
    apt-get install -y -qq gh >/dev/null
    GH_VER=$(gh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    echo -e "${GREEN}  Installed GitHub CLI ${GH_VER}${NC}"
fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}Bootstrap complete. You can now run the ai-cli installer:${NC}"
echo ""
echo "  curl -fsSL https://raw.githubusercontent.com/tetrabit/ai-cli/main/install.sh | bash"
echo ""