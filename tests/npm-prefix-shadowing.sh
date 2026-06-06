#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

fake_bin="$tmp_home/fake-bin"
mkdir -p \
    "$fake_bin" \
    "$tmp_home/.npm-global/bin" \
    "$tmp_home/.npm-global/lib/node_modules" \
    "$tmp_home/.local/bin" \
    "$tmp_home/.local/lib/node_modules" \
    "$tmp_home/.config/fish"

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
            printf '0.133.0\n'
            exit 0
        fi
        ;;
    list)
        package="${3:-}"
        if [[ "$prefix" == "$HOME/.npm-global" && "$package" == "@openai/codex" ]]; then
            printf '{"dependencies":{"@openai/codex":{"version":"0.133.0"}}}\n'
        elif [[ "$prefix" == "$HOME/.local" && "$package" == "@openai/codex" ]]; then
            printf '{"dependencies":{"@openai/codex":{"version":"0.114.0"}}}\n'
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
        if [[ "$prefix" == "$HOME/.local" && "$package" == "@openai/codex" ]]; then
            rm -f "$HOME/.local/bin/codex"
        fi
        exit 0
        ;;
    install)
        printf 'install %s\n' "$*" >> "$HOME/npm-actions.log"
        exit 0
        ;;
esac

printf 'unexpected npm args: %s\n' "$*" >&2
exit 1
FAKE_NPM
chmod +x "$fake_bin/npm"

printf '#!/usr/bin/env bash\necho codex-cli 0.133.0\n' > "$tmp_home/.npm-global/bin/codex"
printf '#!/usr/bin/env bash\necho codex-cli 0.114.0\n' > "$tmp_home/.local/bin/codex"
chmod +x "$tmp_home/.npm-global/bin/codex" "$tmp_home/.local/bin/codex"

cat > "$tmp_home/ai-cli-config" <<'CONFIG'
UPDATE_CLAUDE=0
UPDATE_GH_CLI=0
UPDATE_COPILOT=0
UPDATE_ANTIGRAVITY=0
UPDATE_CODEX=1
UPDATE_PI=0
UPDATE_PI_VS_CLAUDE_CODE=0
UPDATE_HERMES=0
UPDATE_OMX=0
CONFIG

PATH="$fake_bin:$tmp_home/.local/bin:$tmp_home/.npm-global/bin:/usr/bin:/bin" \
HOME="$tmp_home" \
SHELL=/bin/fish \
AI_CLI_CONFIG="$tmp_home/ai-cli-config" \
bash "$repo_root/ai.sh" update --verbose > "$tmp_home/output.txt"

if [[ -e "$tmp_home/.local/bin/codex" ]]; then
    echo "stale ~/.local Codex binary was not removed" >&2
    exit 1
fi

if ! grep -q 'uninstall prefix=.*\.local package=@openai/codex' "$tmp_home/npm-actions.log"; then
    echo "duplicate ~/.local Codex package was not uninstalled" >&2
    exit 1
fi

if ! grep -q 'fish_add_path ".*\.npm-global/bin"' "$tmp_home/.config/fish/config.fish"; then
    echo "managed fish PATH block was not pointed at configured npm prefix" >&2
    exit 1
fi

if ! grep -q 'Already up to date (0.133.0)' "$tmp_home/output.txt"; then
    echo "target npm-global Codex version was not detected as current" >&2
    exit 1
fi

printf 'npm prefix shadowing regression passed\n'
