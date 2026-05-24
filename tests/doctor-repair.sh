#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

mkdir -p \
    "$tmp_home/bin" \
    "$tmp_home/.npm-global/bin" \
    "$tmp_home/.npm-global/lib/node_modules/@mariozechner/pi-coding-agent/dist"

cat > "$tmp_home/bin/npm" <<'FAKE_NPM'
#!/usr/bin/env bash
set -euo pipefail
prefix="${FAKE_NPM_PREFIX:-$HOME/.npm-global}"
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
    if [[ "${args[$i]}" == "--prefix" && $((i + 1)) -lt ${#args[@]} ]]; then
        prefix="${args[$((i + 1))]}"
    fi
done

case "${1:-}" in
    config)
        if [[ "${2:-}" == "get" && "${3:-}" == "prefix" ]]; then
            printf '%s\n' "${FAKE_NPM_PREFIX:-$HOME/.npm-global}"
            exit 0
        fi
        ;;
    list)
        package="${3:-}"
        if [[ "$package" == "@mariozechner/pi-coding-agent" && -e "$prefix/lib/node_modules/@mariozechner/pi-coding-agent" ]]; then
            printf '{"dependencies":{"@mariozechner/pi-coding-agent":{"version":"0.65.2"}}}\n'
        else
            printf '{"dependencies":{}}\n'
        fi
        exit 0
        ;;
    uninstall)
        package=""
        for arg in "$@"; do
            [[ "$arg" == @*/* ]] && package="$arg"
        done
        printf 'uninstall prefix=%s package=%s\n' "$prefix" "$package" >> "$HOME/npm-actions.log"
        if [[ "$package" == "@mariozechner/pi-coding-agent" ]]; then
            rm -f "$prefix/bin/pi"
            rm -rf "$prefix/lib/node_modules/@mariozechner/pi-coding-agent"
        fi
        exit 0
        ;;
esac

printf 'unexpected npm args: %s\n' "$*" >&2
exit 1
FAKE_NPM
chmod +x "$tmp_home/bin/npm"

printf '#!/usr/bin/env bash\necho stale ai\n' > "$tmp_home/bin/ai"
chmod +x "$tmp_home/bin/ai"

printf '#!/usr/bin/env bash\necho pi 0.65.2\n' > "$tmp_home/.npm-global/lib/node_modules/@mariozechner/pi-coding-agent/dist/cli.js"
chmod +x "$tmp_home/.npm-global/lib/node_modules/@mariozechner/pi-coding-agent/dist/cli.js"
ln -s ../lib/node_modules/@mariozechner/pi-coding-agent/dist/cli.js "$tmp_home/.npm-global/bin/pi"

cat > "$tmp_home/ai-cli-config" <<'CONFIG'
UPDATE_CLAUDE=0
UPDATE_GH_CLI=0
UPDATE_COPILOT=0
UPDATE_ANTIGRAVITY=0
UPDATE_CODEX=0
UPDATE_PI=1
UPDATE_PI_VS_CLAUDE_CODE=0
UPDATE_HERMES=0
CONFIG

PATH="$tmp_home/bin:/usr/bin:/bin" \
HOME="$tmp_home" \
AI_CLI_CONFIG="$tmp_home/ai-cli-config" \
bash "$repo_root/ai.sh" doctor > "$tmp_home/output.txt"

if ! cmp -s "$repo_root/ai.sh" "$tmp_home/bin/ai"; then
    echo "doctor did not replace stale ai launcher" >&2
    exit 1
fi

if ! grep -q 'uninstall prefix=.*\.npm-global package=@mariozechner/pi-coding-agent' "$tmp_home/npm-actions.log"; then
    echo "doctor did not remove legacy Pi package" >&2
    exit 1
fi

if [[ -e "$tmp_home/.npm-global/bin/pi" ]]; then
    echo "doctor left the legacy Pi binary in place" >&2
    exit 1
fi

if ! grep -q 'Doctor checks complete' "$tmp_home/output.txt"; then
    echo "doctor did not report successful completion" >&2
    exit 1
fi

printf 'doctor repair regression passed\n'
