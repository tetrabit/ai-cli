#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

fake_bin="$tmp_home/fake-bin"
mkdir -p \
    "$fake_bin" \
    "$tmp_home/.npm-global/bin" \
    "$tmp_home/.npm-global/lib/node_modules/@mariozechner/pi-coding-agent/dist" \
    "$tmp_home/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/dist"

cat > "$fake_bin/npm" <<'FAKE_NPM'
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
    view)
        if [[ "${3:-}" == "version" ]]; then
            printf '0.75.5\n'
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
    install)
        printf 'install %s\n' "$*" >> "$HOME/npm-actions.log"
        if [[ -e "$prefix/bin/pi" || -L "$prefix/bin/pi" ]]; then
            printf 'npm error EEXIST: file already exists: %s\n' "$prefix/bin/pi" >&2
            exit 17
        fi
        printf '#!/usr/bin/env bash\necho pi 0.75.5\n' > "$prefix/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
        chmod +x "$prefix/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
        ln -s ../lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js "$prefix/bin/pi"
        exit 0
        ;;
esac

printf 'unexpected npm args: %s\n' "$*" >&2
exit 1
FAKE_NPM
chmod +x "$fake_bin/npm"

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

PATH="$fake_bin:$tmp_home/.npm-global/bin:/usr/bin:/bin" \
HOME="$tmp_home" \
AI_CLI_CONFIG="$tmp_home/ai-cli-config" \
bash "$repo_root/ai.sh" update --verbose > "$tmp_home/output.txt"

if ! grep -q 'uninstall prefix=.*\.npm-global package=@mariozechner/pi-coding-agent' "$tmp_home/npm-actions.log"; then
    echo "legacy Pi package was not uninstalled before install" >&2
    exit 1
fi

if ! grep -q 'install install -g @earendil-works/pi-coding-agent@latest' "$tmp_home/npm-actions.log"; then
    echo "new Pi package was not installed" >&2
    exit 1
fi

if [[ "$(readlink "$tmp_home/.npm-global/bin/pi")" != "../lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js" ]]; then
    echo "Pi binary was not repointed to the new package" >&2
    exit 1
fi

if ! grep -q 'Removing legacy Pi Coding Agent 0.65.2' "$tmp_home/output.txt"; then
    echo "legacy cleanup was not reported" >&2
    exit 1
fi

printf 'npm legacy bin conflict regression passed\n'
