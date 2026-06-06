#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

fake_bin="$tmp_home/bin"
mkdir -p "$fake_bin"
printf '2.87.0\n' > "$tmp_home/gh-version"

cat > "$tmp_home/os-release" <<'OS_RELEASE'
ID=bazzite
ID_LIKE=fedora
OS_RELEASE

cat > "$fake_bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    --version)
        printf 'gh version %s\n' "$(cat "$HOME/gh-version")"
        ;;
    *)
        printf 'unexpected gh args: %s\n' "$*" >&2
        exit 1
        ;;
esac
FAKE_GH
chmod +x "$fake_bin/gh"

cat > "$fake_bin/brew" <<'FAKE_BREW'
#!/usr/bin/env bash
set -euo pipefail

printf 'brew %s\n' "$*" >> "$HOME/package-actions.log"
if [[ "${1:-}" == "upgrade" && "${2:-}" == "gh" ]]; then
    printf '2.88.0\n' > "$HOME/gh-version"
fi
FAKE_BREW
chmod +x "$fake_bin/brew"

for tool in dnf rpm-ostree; do
    cat > "$fake_bin/$tool" <<'FAKE_LAYERING_TOOL'
#!/usr/bin/env bash
set -euo pipefail
printf 'unexpected layered package tool: %s\n' "$0" >&2
exit 1
FAKE_LAYERING_TOOL
    chmod +x "$fake_bin/$tool"
done

cat > "$tmp_home/ai-cli-config" <<'CONFIG'
UPDATE_CLAUDE=0
UPDATE_GH_CLI=1
UPDATE_COPILOT=0
UPDATE_ANTIGRAVITY=0
UPDATE_CODEX=0
UPDATE_PI=0
UPDATE_PI_VS_CLAUDE_CODE=0
UPDATE_HERMES=0
UPDATE_OMX=0
CONFIG

PATH="$fake_bin:/usr/bin:/bin" \
HOME="$tmp_home" \
AI_CLI_CONFIG="$tmp_home/ai-cli-config" \
AI_CLI_OS_RELEASE="$tmp_home/os-release" \
AI_CLI_BAZZITE_BREW_BIN="$fake_bin" \
bash "$repo_root/ai.sh" update > "$tmp_home/output.txt"

if ! grep -q '^brew upgrade gh$' "$tmp_home/package-actions.log"; then
    echo "Bazzite GitHub CLI update did not use brew" >&2
    exit 1
fi

if grep -Eq 'dnf|rpm-ostree' "$tmp_home/package-actions.log" "$tmp_home/output.txt"; then
    echo "Bazzite GitHub CLI update attempted layered/system package tooling" >&2
    exit 1
fi

if ! grep -q 'Updated 2.87.0 -> 2.88.0' "$tmp_home/output.txt"; then
    echo "Bazzite GitHub CLI update did not report the brew-updated version" >&2
    exit 1
fi

printf 'bazzite gh brew regression passed\n'
