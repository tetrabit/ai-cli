#!/usr/bin/env bash
set -euo pipefail

REPO="tetrabit/ai-cli"
RAW="https://raw.githubusercontent.com/$REPO/main"

echo "Detecting operating system..."

case "$(uname -s)" in
    Linux*|Darwin*)
        INSTALL_DIR="/usr/local/bin"
        echo "Detected: $(uname -s)"
        echo "Installing ai -> $INSTALL_DIR/ai"

        if [ -w "$INSTALL_DIR" ]; then
            curl -fsSL "$RAW/ai.sh" -o "$INSTALL_DIR/ai"
            chmod +x "$INSTALL_DIR/ai"
        else
            sudo curl -fsSL "$RAW/ai.sh" -o "$INSTALL_DIR/ai"
            sudo chmod +x "$INSTALL_DIR/ai"
        fi

        echo "Installed successfully. Run 'ai' to get started."
        ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT*)
        INSTALL_DIR="C:\\tools"
        echo "Detected: Windows"
        echo "Installing ai.ps1 -> $INSTALL_DIR\\ai.ps1"

        mkdir -p "$(cygpath "$INSTALL_DIR" 2>/dev/null || echo "/c/tools")"
        curl -fsSL "$RAW/ai.ps1" -o "$(cygpath "$INSTALL_DIR/ai.ps1" 2>/dev/null || echo "/c/tools/ai.ps1")"

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
