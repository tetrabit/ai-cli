#!/usr/bin/env bash
set -euo pipefail

REPO="tetrabit/ai-cli"
RAW="https://raw.githubusercontent.com/$REPO/main"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR=""

if [[ -n "$SCRIPT_SOURCE" && -f "$SCRIPT_SOURCE" ]]; then
    SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
fi

linux_source_path() {
    if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/ai.sh" ]]; then
        printf '%s\n' "$SCRIPT_DIR/ai.sh"
    else
        printf '%s\n' "$RAW/ai.sh"
    fi
}

windows_source_path() {
    if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/ai.ps1" ]]; then
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
        if [[ -w "$dest_dir" ]]; then
            install -m "$mode" "$source" "$dest"
        else
            sudo install -m "$mode" "$source" "$dest"
        fi
        return
    fi

    local temp_file
    temp_file="$(mktemp)"
    trap 'rm -f "$temp_file"' RETURN
    curl -fsSL "$source" -o "$temp_file"
    if [[ -w "$dest_dir" ]]; then
        install -m "$mode" "$temp_file" "$dest"
    else
        sudo install -m "$mode" "$temp_file" "$dest"
    fi
}

echo "Detecting operating system..."

case "$(uname -s)" in
    Linux*|Darwin*)
        INSTALL_DIR="${AI_CLI_INSTALL_DIR:-/usr/local/bin}"
        SOURCE_PATH="$(linux_source_path)"
        echo "Detected: $(uname -s)"
        echo "Installing ai -> $INSTALL_DIR/ai"
        install_file "$SOURCE_PATH" "$INSTALL_DIR/ai" 0755

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
            cp "$SOURCE_PATH" "$TARGET_PATH"
        else
            curl -fsSL "$SOURCE_PATH" -o "$TARGET_PATH"
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
