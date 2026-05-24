#!/usr/bin/env bash
set -euo pipefail

REPO="tetrabit/ai-cli"
RAW_HOST="https://raw.githubusercontent.com"
REMOTE_REF="${AI_CLI_REF:-}"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR=""

USE_LOCAL=false
FORCE_REMOTE=false
for arg in "$@"; do
    case "$arg" in
        --local) USE_LOCAL=true ;;
        --remote) FORCE_REMOTE=true ;;
    esac
done

if [[ -n "$SCRIPT_SOURCE" && -f "$SCRIPT_SOURCE" ]]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
fi

resolve_remote_ref() {
    if [[ -n "$REMOTE_REF" ]]; then
        printf '%s\n' "$REMOTE_REF"
        return
    fi

    local sha=""
    sha=$(
        curl -fsSL "https://api.github.com/repos/$REPO/commits/main" 2>/dev/null \
            | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{40\}\)".*/\1/p' \
            | head -n 1
    ) || true

    if [[ -n "$sha" ]]; then
        REMOTE_REF="$sha"
    else
        REMOTE_REF="main"
    fi

    printf '%s\n' "$REMOTE_REF"
}

remote_source_path() {
    local file="$1"
    printf '%s/%s/%s/%s\n' "$RAW_HOST" "$REPO" "$(resolve_remote_ref)" "$file"
}

local_sources_available() {
    [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/ai.sh" && -f "$SCRIPT_DIR/ai.ps1" ]]
}

should_use_local_sources() {
    ! $FORCE_REMOTE && { $USE_LOCAL || local_sources_available; }
}

linux_source_path() {
    if should_use_local_sources && [[ -f "$SCRIPT_DIR/ai.sh" ]]; then
        printf '%s\n' "$SCRIPT_DIR/ai.sh"
    else
        remote_source_path "ai.sh"
    fi
}

windows_source_path() {
    if should_use_local_sources && [[ -f "$SCRIPT_DIR/ai.ps1" ]]; then
        printf '%s\n' "$SCRIPT_DIR/ai.ps1"
    else
        remote_source_path "ai.ps1"
    fi
}

prepend_path_dir() {
    local dir="$1"
    local item new_path old_ifs

    [[ -d "$dir" ]] || return 0
    new_path="$dir"
    old_ifs="$IFS"
    IFS=:
    for item in ${PATH:-}; do
        [[ -n "$item" && "$item" != "$dir" ]] || continue
        new_path="${new_path}:$item"
    done
    IFS="$old_ifs"
    PATH="$new_path"
}

prompt_for_sudo() {
    local action="$1"

    if ! command -v sudo >/dev/null 2>&1; then
        echo "sudo is required to $action, but sudo was not found."
        return 1
    fi

    echo "sudo is required to $action."
    if [[ ! -t 0 ]]; then
        echo "Run this installer from an interactive terminal to enter your sudo password."
        return 1
    fi

    sudo -v
}

package_manager() {
    if command -v pacman >/dev/null 2>&1; then
        printf 'pacman\n'
    elif command -v apt-get >/dev/null 2>&1; then
        printf 'apt\n'
    elif command -v dnf >/dev/null 2>&1; then
        printf 'dnf\n'
    elif command -v brew >/dev/null 2>&1; then
        printf 'brew\n'
    else
        printf 'none\n'
    fi
}

packages_for_dependency() {
    local manager="$1"
    local dependency="$2"

    case "$manager:$dependency" in
        pacman:curl) printf 'curl\n' ;;
        pacman:git) printf 'git\n' ;;
        pacman:python3) printf 'python\n' ;;
        pacman:npm) printf 'nodejs\nnpm\n' ;;
        pacman:gh) printf 'github-cli\n' ;;
        pacman:unzip) printf 'unzip\n' ;;
        pacman:just) printf 'just\n' ;;
        apt:curl) printf 'curl\n' ;;
        apt:git) printf 'git\n' ;;
        apt:python3) printf 'python3\n' ;;
        apt:npm) printf 'nodejs\nnpm\n' ;;
        apt:gh) printf 'gh\n' ;;
        apt:unzip) printf 'unzip\n' ;;
        apt:just) printf 'just\n' ;;
        dnf:curl) printf 'curl\n' ;;
        dnf:git) printf 'git\n' ;;
        dnf:python3) printf 'python3\n' ;;
        dnf:npm) printf 'nodejs\nnpm\n' ;;
        dnf:gh) printf 'gh\n' ;;
        dnf:unzip) printf 'unzip\n' ;;
        dnf:just) printf 'just\n' ;;
        brew:curl) printf 'curl\n' ;;
        brew:git) printf 'git\n' ;;
        brew:python3) printf 'python\n' ;;
        brew:npm) printf 'node\n' ;;
        brew:gh) printf 'gh\n' ;;
        brew:unzip) printf 'unzip\n' ;;
        brew:just) printf 'just\n' ;;
        *) return 1 ;;
    esac
}

install_packages() {
    local manager="$1"
    shift
    local -a packages=("$@")

    [[ ${#packages[@]} -gt 0 ]] || return 0

    case "$manager" in
        pacman)
            prompt_for_sudo "install ${packages[*]}" || return 1
            sudo pacman -Sy --noconfirm --needed "${packages[@]}" >/dev/null
            ;;
        apt)
            prompt_for_sudo "install ${packages[*]}" || return 1
            sudo apt-get update -qq >/dev/null
            sudo apt-get install -y -qq "${packages[@]}" >/dev/null
            ;;
        dnf)
            prompt_for_sudo "install ${packages[*]}" || return 1
            sudo dnf install -y -q "${packages[@]}" >/dev/null
            ;;
        brew)
            brew install "${packages[@]}" >/dev/null
            ;;
        *)
            echo "No supported package manager found for ${packages[*]}."
            return 1
            ;;
    esac
}

ensure_package_dependency() {
    local dependency="$1"
    local display_name="$2"
    local manager
    local package packages_text
    local -a packages=()

    manager="$(package_manager)"
    if [[ "$manager" == "apt" && "$dependency" == "gh" ]]; then
        ensure_command_dependency curl curl "curl" || return 1
        if [[ ! -f /etc/apt/sources.list.d/github-cli.list || ! -f /usr/share/keyrings/githubcli-archive-keyring.gpg ]]; then
            prompt_for_sudo "configure the GitHub CLI apt repository" || return 1
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null 2>&1
            sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
        fi
    fi

    if ! packages_text=$(packages_for_dependency "$manager" "$dependency"); then
        echo "Could not map $display_name to a package for this system."
        return 1
    fi
    while IFS= read -r package; do
        [[ -n "$package" ]] && packages+=("$package")
    done <<< "$packages_text"

    echo "$display_name is missing, installing..."
    install_packages "$manager" "${packages[@]}"
}

ensure_command_dependency() {
    local command_name="$1"
    local dependency="$2"
    local display_name="$3"

    if command -v "$command_name" >/dev/null 2>&1; then
        return 0
    fi

    ensure_package_dependency "$dependency" "$display_name" || return 1
    command -v "$command_name" >/dev/null 2>&1
}

ensure_bun_dependency() {
    prepend_path_dir "$HOME/.bun/bin"
    if command -v bun >/dev/null 2>&1; then
        return 0
    fi

    echo "Bun is missing, installing..."
    ensure_command_dependency curl curl "curl" || return 1
    if [[ "$(uname -s)" == Linux* ]]; then
        ensure_command_dependency unzip unzip "unzip" || return 1
    fi

    curl -fsSL https://bun.com/install | bash >/dev/null
    prepend_path_dir "$HOME/.bun/bin"
    command -v bun >/dev/null 2>&1
}

ensure_just_dependency() {
    if command -v just >/dev/null 2>&1; then
        return 0
    fi

    if [[ "${AI_CLI_JUST_CHECKED:-0}" == "1" ]]; then
        return 0
    fi
    AI_CLI_JUST_CHECKED=1

    ensure_package_dependency just "just" || {
        echo "just is still missing; Pi vs Claude Code recipes will not run until just is installed."
        return 0
    }

    if ! command -v just >/dev/null 2>&1; then
        echo "just is still missing; Pi vs Claude Code recipes will not run until just is installed."
    fi
}

ensure_unix_dependencies() {
    echo "Checking ai-cli dependencies..."
    ensure_command_dependency curl curl "curl"
    ensure_command_dependency git git "Git"
    ensure_command_dependency python3 python3 "Python 3"
    ensure_command_dependency npm npm "Node.js/npm"
    ensure_command_dependency gh gh "GitHub CLI"
    ensure_bun_dependency
    ensure_just_dependency
    echo "Dependencies ready."
}

ensure_windows_command_dependency() {
    local command_name="$1"
    local package_id="$2"
    local display_name="$3"

    if command -v "$command_name" >/dev/null 2>&1; then
        return 0
    fi

    if ! command -v winget >/dev/null 2>&1; then
        echo "$display_name is missing and winget was not found."
        return 1
    fi

    echo "$display_name is missing, installing..."
    winget install --id "$package_id" --exact --silent --accept-package-agreements --accept-source-agreements
    command -v "$command_name" >/dev/null 2>&1
}

ensure_windows_dependencies() {
    echo "Checking ai-cli dependencies..."
    ensure_windows_command_dependency git Git.Git "Git"
    ensure_windows_command_dependency node OpenJS.NodeJS.LTS "Node.js"
    ensure_windows_command_dependency npm OpenJS.NodeJS.LTS "npm"
    ensure_windows_command_dependency gh GitHub.cli "GitHub CLI"
    ensure_windows_command_dependency bun Oven-sh.Bun "Bun"
    ensure_windows_command_dependency just Casey.Just "just" || true
    echo "Dependencies ready."
}

install_file() {
    local source="$1"
    local dest="$2"
    local mode="$3"
    local dest_dir

    dest_dir="$(dirname "$dest")"
    if [[ ! -d "$dest_dir" ]]; then
        if [[ -w "$(dirname "$dest_dir")" ]]; then
            mkdir -p "$dest_dir"
        else
            prompt_for_sudo "create $dest_dir" || return 1
            sudo mkdir -p "$dest_dir"
        fi
    fi

    if [[ -f "$source" ]]; then
        echo "Installing from local source: $source"
        if [[ -w "$dest_dir" ]]; then
            install -m "$mode" "$source" "$dest"
        else
            prompt_for_sudo "install $dest" || return 1
            sudo install -m "$mode" "$source" "$dest"
        fi
        return
    fi

    echo "Downloading from: $source"
    local temp_file
    temp_file="$(mktemp)"
    trap 'rm -f "$temp_file"' RETURN
    # Add a cache-busting query parameter for raw.githubusercontent.com
    curl -fsSL "${source}?$(date +%s)" -o "$temp_file"
    if [[ -w "$dest_dir" ]]; then
        install -m "$mode" "$temp_file" "$dest"
    else
        prompt_for_sudo "install $dest" || return 1
        sudo install -m "$mode" "$temp_file" "$dest"
    fi
}

echo "Detecting operating system..."

case "$(uname -s)" in
    Linux*|Darwin*)
        # If ai is already in PATH, try to overwrite that one specifically
        # unless AI_CLI_INSTALL_DIR is set.
        CURRENT_AI="$(which ai 2>/dev/null || true)"
        if [[ -n "${AI_CLI_INSTALL_DIR:-}" ]]; then
            INSTALL_DIR="$AI_CLI_INSTALL_DIR"
            INSTALL_PATH="$INSTALL_DIR/ai"
        elif [[ -n "$CURRENT_AI" ]]; then
            INSTALL_PATH="$CURRENT_AI"
            INSTALL_DIR="$(dirname "$INSTALL_PATH")"
        else
            INSTALL_DIR="/usr/local/bin"
            INSTALL_PATH="$INSTALL_DIR/ai"
        fi

        SOURCE_PATH="$(linux_source_path)"
        echo "Detected: $(uname -s)"
        ensure_unix_dependencies
        echo "Installing ai -> $INSTALL_PATH"
        install_file "$SOURCE_PATH" "$INSTALL_PATH" 0755

        # Check if there are other 'ai' binaries in PATH that might shadow this one
        ALL_AIS="$(which -a ai 2>/dev/null || true)"
        FIRST_AI="$(echo "$ALL_AIS" | head -n 1)"
        if [[ -n "$FIRST_AI" && "$FIRST_AI" != "$INSTALL_PATH" ]]; then
            echo ""
            echo "WARNING: The 'ai' command you just installed at $INSTALL_PATH"
            echo "is being shadowed by another 'ai' at $FIRST_AI"
            echo "which appears earlier in your PATH."
            echo ""
            echo "To fix this, you may want to remove $FIRST_AI"
            echo "or update your PATH to prioritize $INSTALL_DIR."
        fi

        echo "Installed successfully. Run 'ai' to get started."
        ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT*)
        INSTALL_DIR="${AI_CLI_WINDOWS_INSTALL_DIR:-C:\\tools}"
        SOURCE_PATH="$(windows_source_path)"
        TARGET_PATH="$(cygpath "$INSTALL_DIR/ai.ps1" 2>/dev/null || echo "/c/tools/ai.ps1")"
        echo "Detected: Windows"
        ensure_windows_dependencies
        echo "Installing ai.ps1 -> $INSTALL_DIR\\ai.ps1"

        mkdir -p "$(cygpath "$INSTALL_DIR" 2>/dev/null || echo "/c/tools")"
        if [[ -f "$SOURCE_PATH" ]]; then
            echo "Installing from local source: $SOURCE_PATH"
            cp "$SOURCE_PATH" "$TARGET_PATH"
        else
            echo "Downloading from: $SOURCE_PATH"
            curl -fsSL "${SOURCE_PATH}?$(date +%s)" -o "$TARGET_PATH"
        fi

        # Create ai.cmd wrapper if it doesn't exist
        CMD_PATH="$(cygpath "$INSTALL_DIR/ai.cmd" 2>/dev/null || echo "/c/tools/ai.cmd")"
        if [ ! -f "$CMD_PATH" ]; then
            printf '@powershell -NoProfile -ExecutionPolicy Bypass -File "%%~dp0ai.ps1" %%*\r\n' > "$CMD_PATH"
            echo "Created ai.cmd wrapper."
        fi

        echo "Installed successfully."
        echo "Make sure $INSTALL_DIR is in your PATH, then run 'ai' to get started."
        ;;
    *)
        echo "Unsupported OS: $(uname -s)"
        exit 1
        ;;
esac
