#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

fake_bin="$tmp_home/bin"
repo_dir="$tmp_home/pi-vs-claude-code"
mkdir -p "$fake_bin"

cat > "$fake_bin/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == *"https://bun.com/install"* ]]; then
    cat <<'BUN_INSTALL'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/.bun/bin"
cat > "$HOME/.bun/bin/bun" <<'BUN'
#!/usr/bin/env bash
set -euo pipefail
printf 'bun %s\n' "$*" >> "$HOME/bun-actions.log"
BUN
chmod +x "$HOME/.bun/bin/bun"
BUN_INSTALL
    exit 0
fi

printf 'unexpected curl args: %s\n' "$*" >&2
exit 1
FAKE_CURL
chmod +x "$fake_bin/curl"

cat > "$fake_bin/git" <<'FAKE_GIT'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    clone)
        mkdir -p "$3/.git"
        printf 'clone %s %s\n' "$2" "$3" >> "$HOME/git-actions.log"
        ;;
    -C)
        case "${3:-}" in
            rev-parse) printf 'abc123\n' ;;
            pull) printf 'Already up to date.\n' ;;
            *) printf 'unexpected git -C args: %s\n' "$*" >&2; exit 1 ;;
        esac
        ;;
    *)
        printf 'unexpected git args: %s\n' "$*" >&2
        exit 1
        ;;
esac
FAKE_GIT
chmod +x "$fake_bin/git"

printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/just"
chmod +x "$fake_bin/just"

cat > "$tmp_home/ai-cli-config" <<'CONFIG'
UPDATE_CLAUDE=0
UPDATE_GH_CLI=0
UPDATE_COPILOT=0
UPDATE_ANTIGRAVITY=0
UPDATE_CODEX=0
UPDATE_PI=0
UPDATE_PI_VS_CLAUDE_CODE=1
UPDATE_HERMES=0
UPDATE_OMX=0
CONFIG

PATH="$fake_bin:/usr/bin:/bin" \
HOME="$tmp_home" \
AI_CLI_CONFIG="$tmp_home/ai-cli-config" \
AI_CLI_PI_VS_CLAUDE_CODE_DIR="$repo_dir" \
bash "$repo_root/ai.sh" update > "$tmp_home/output.txt"

if ! grep -q 'Bun is missing, installing' "$tmp_home/output.txt"; then
    echo "update did not report installing missing Bun" >&2
    exit 1
fi

if ! grep -q "install --cwd $repo_dir" "$tmp_home/bun-actions.log"; then
    echo "bun install was not run for Pi vs Claude Code" >&2
    exit 1
fi

if ! grep -q "clone https://github.com/disler/pi-vs-claude-code.git $repo_dir" "$tmp_home/git-actions.log"; then
    echo "Pi vs Claude Code repo was not cloned" >&2
    exit 1
fi

printf 'pi-vs bun install regression passed\n'
