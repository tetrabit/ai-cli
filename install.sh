#!/usr/bin/env bash
set -euo pipefail

REPO="tetrabit/ai-cli"
RAW="https://raw.githubusercontent.com/$REPO/main"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR=""

USE_LOCAL=false
for arg in "$@"; do
    if [[ "$arg" == "--local" ]]; then
        USE_LOCAL=true
    fi
done

if [[ -n "$SCRIPT_SOURCE" && -f "$SCRIPT_SOURCE" ]]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
fi

linux_source_path() {
    if $USE_LOCAL && [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/ai.sh" ]]; then
        printf '%s\n' "$SCRIPT_DIR/ai.sh"
    else
        printf '%s\n' "$RAW/ai.sh"
    fi
}

windows_source_path() {
    if $USE_LOCAL && [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/ai.ps1" ]]; then
        printf '%s\n' "$SCRIPT_DIR/ai.ps1"
    else
        printf '%s\n' "$RAW/ai.ps1"
    fi
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
            sudo mkdir -p "$dest_dir"
        fi
    fi

    if [[ -f "$source" ]]; then
        echo "Installing from local source: $source"
        if [[ -w "$dest_dir" ]]; then
            install -m "$mode" "$source" "$dest"
        else
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
