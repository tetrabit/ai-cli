#!/usr/bin/env bash
set -euo pipefail

# Bootstrap prerequisites for ai-cli on Debian/Ubuntu, Arch Linux, and Bazzite.
# Debian/Ubuntu and Arch must be run as root. Bazzite must be run as a normal user.

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# ── Distro detection ────────────────────────────────────────────────
DISTRO_ID=""
OS_RELEASE_FILE="${AI_CLI_OS_RELEASE:-/etc/os-release}"
if [ -f "$OS_RELEASE_FILE" ]; then
    # shellcheck source=/dev/null
    . "$OS_RELEASE_FILE"
    DISTRO_ID="${ID:-}"
fi

case "$DISTRO_ID" in
    bazzite)
        PKG_MANAGER="bazzite"
        ;;
    arch|cachyos|endeavouros|manjaro)
        PKG_MANAGER="arch"
        ;;
    ubuntu|debian|linuxmint|pop)
        PKG_MANAGER="apt"
        ;;
    *)
        echo -e "${RED}Unsupported distro: '${DISTRO_ID}'. Supported: Bazzite, Arch Linux, Debian/Ubuntu.${NC}"
        exit 1
        ;;
esac

if [[ "$PKG_MANAGER" == "bazzite" ]]; then
    if [[ $EUID -eq 0 ]]; then
        echo -e "${RED}Error: Bazzite bootstrap must be run without sudo so Homebrew installs into the user environment.${NC}"
        exit 1
    fi
else
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: this script must be run as root (sudo ./bootstrap.sh)${NC}"
        exit 1
    fi
fi

echo -e "${CYAN}==> Detected distro: ${DISTRO_ID} (using ${PKG_MANAGER})${NC}"

# ── Bazzite bootstrap ────────────────────────────────────────────────
if [[ "$PKG_MANAGER" == "bazzite" ]]; then

    prepend_brew_path() {
        local dir="$1"
        [[ -d "$dir" ]] || return 0
        case ":$PATH:" in
            *":$dir:"*) ;;
            *) PATH="$dir:$PATH" ;;
        esac
    }

    brew_install_if_missing() {
        local command_name="$1"
        local package="$2"
        local label="$3"

        if command -v "$command_name" &>/dev/null; then
            local version
            version=$("$command_name" --version 2>/dev/null | head -n 1 || true)
            echo -e "${GREEN}  Already installed: ${label}${version:+ (${version})}${NC}"
            return 0
        fi

        echo -e "${YELLOW}  Installing ${label} with Homebrew...${NC}"
        brew install "$package" >/dev/null
        if ! command -v "$command_name" &>/dev/null; then
            echo -e "${RED}  ${label} was not found after brew install ${package}${NC}"
            return 1
        fi
        echo -e "${GREEN}  Installed ${label}${NC}"
    }

    prepend_brew_path "/home/linuxbrew/.linuxbrew/bin"
    prepend_brew_path "$HOME/.linuxbrew/bin"

    if ! command -v brew &>/dev/null; then
        echo -e "${RED}Homebrew was not found.${NC}"
        echo -e "${YELLOW}Install Homebrew from the Bazzite Portal or Bold Brew, then rerun ./bootstrap.sh.${NC}"
        echo -e "${YELLOW}This script intentionally avoids rpm-ostree on Bazzite because package layering can interfere with Bazzite update checks.${NC}"
        exit 1
    fi

    echo -e "${CYAN}==> Installing CLI prerequisites with Homebrew...${NC}"
    brew_install_if_missing curl curl curl
    brew_install_if_missing git git Git
    brew_install_if_missing python3 python "Python 3"
    brew_install_if_missing node node Node.js
    brew_install_if_missing npm node npm
    brew_install_if_missing gh gh "GitHub CLI"
    brew_install_if_missing unzip unzip unzip
    brew_install_if_missing just just just

# ── Arch Linux bootstrap ─────────────────────────────────────────────
elif [[ "$PKG_MANAGER" == "arch" ]]; then

    echo -e "${CYAN}==> Updating pacman package index...${NC}"
    pacman -Sy --noconfirm >/dev/null

    echo -e "${CYAN}==> Installing core utilities (curl, git, python, gnupg)...${NC}"
    pacman -S --noconfirm --needed curl git python gnupg ca-certificates >/dev/null
    echo -e "${GREEN}  Done${NC}"

    echo ""
    echo -e "${CYAN}==> Checking Node.js...${NC}"
    if command -v node &>/dev/null; then
        NODE_VER=$(node --version 2>/dev/null || true)
        echo -e "${GREEN}  Already installed (${NODE_VER})${NC}"
    else
        echo -e "${YELLOW}  Installing Node.js and npm from pacman...${NC}"
        pacman -S --noconfirm --needed nodejs npm >/dev/null
        NODE_VER=$(node --version 2>/dev/null || true)
        echo -e "${GREEN}  Installed Node.js ${NODE_VER}${NC}"
    fi

    if ! command -v npm &>/dev/null; then
        echo -e "${RED}  npm not found after Node.js install — something went wrong${NC}"
        exit 1
    fi
    NPM_VER=$(npm --version 2>/dev/null || true)
    echo -e "${GREEN}  npm ${NPM_VER}${NC}"

    echo ""
    echo -e "${CYAN}==> Checking GitHub CLI...${NC}"
    if command -v gh &>/dev/null; then
        GH_VER=$(gh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        echo -e "${GREEN}  Already installed (${GH_VER})${NC}"
    else
        echo -e "${YELLOW}  Installing GitHub CLI from pacman...${NC}"
        pacman -S --noconfirm --needed github-cli >/dev/null
        GH_VER=$(gh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        echo -e "${GREEN}  Installed GitHub CLI ${GH_VER}${NC}"
    fi

# ── Debian/Ubuntu bootstrap ──────────────────────────────────────────
else

    echo -e "${CYAN}==> Updating apt package index...${NC}"
    apt-get update -qq

    echo -e "${CYAN}==> Installing core utilities (curl, git, python3)...${NC}"
    apt-get install -y -qq curl git python3 ca-certificates gnupg >/dev/null
    echo -e "${GREEN}  Done${NC}"

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

    if ! command -v npm &>/dev/null; then
        echo -e "${RED}  npm not found after Node.js install — something went wrong${NC}"
        exit 1
    fi
    NPM_VER=$(npm --version 2>/dev/null || true)
    echo -e "${GREEN}  npm ${NPM_VER}${NC}"

    echo ""
    echo -e "${CYAN}==> Checking GitHub CLI...${NC}"
    if command -v gh &>/dev/null; then
        GH_VER=$(gh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        echo -e "${GREEN}  Already installed (${GH_VER})${NC}"
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

fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}Bootstrap complete. You can now run the ai-cli installer:${NC}"
echo ""
echo "  curl -fsSL https://raw.githubusercontent.com/tetrabit/ai-cli/refs/heads/main/install.sh | bash"
echo ""
