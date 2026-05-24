#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

fake_bin="$tmp_home/bin"
mkdir -p "$fake_bin"
printf 'v0.8.0\n' > "$tmp_home/hermes-version"

cat > "$fake_bin/hermes" <<'FAKE_HERMES'
#!/usr/bin/env bash
set -euo pipefail

version="$(cat "$HOME/hermes-version")"
case "${1:-}" in
    --version|version)
        printf 'Hermes Agent %s\n' "$version"
        ;;
    update)
        printf 'update from %s\n' "$version" >> "$HOME/hermes-actions.log"
        case "$version" in
            v0.8.0) printf 'v0.9.0\n' > "$HOME/hermes-version" ;;
            v0.9.0) printf 'v0.10.0\n' > "$HOME/hermes-version" ;;
            *) printf 'Up to date\n' ;;
        esac
        ;;
    *)
        printf 'unexpected hermes args: %s\n' "$*" >&2
        exit 1
        ;;
esac
FAKE_HERMES
chmod +x "$fake_bin/hermes"

printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/curl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/git"
chmod +x "$fake_bin/curl" "$fake_bin/git"

cat > "$tmp_home/ai-cli-config" <<'CONFIG'
UPDATE_CLAUDE=0
UPDATE_GH_CLI=0
UPDATE_COPILOT=0
UPDATE_ANTIGRAVITY=0
UPDATE_CODEX=0
UPDATE_PI=0
UPDATE_PI_VS_CLAUDE_CODE=0
UPDATE_HERMES=1
CONFIG

PATH="$fake_bin:/usr/bin:/bin" \
HOME="$tmp_home" \
AI_CLI_CONFIG="$tmp_home/ai-cli-config" \
bash "$repo_root/ai.sh" update > "$tmp_home/output.txt"

if ! grep -q 'Updated v0.8.0 -> v0.10.0' "$tmp_home/output.txt"; then
    echo "Hermes update did not loop to the final version" >&2
    exit 1
fi

if [[ "$(wc -l < "$tmp_home/hermes-actions.log")" -ne 3 ]]; then
    echo "Hermes update did not run until version stabilized" >&2
    exit 1
fi

printf 'hermes update loop regression passed\n'
