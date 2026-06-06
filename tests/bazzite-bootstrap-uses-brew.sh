#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

fake_bin="$tmp_home/bin"
brew_bin="$tmp_home/.linuxbrew/bin"
mkdir -p "$fake_bin" "$brew_bin"

cat > "$tmp_home/os-release" <<'OS_RELEASE'
ID=bazzite
ID_LIKE=fedora
OS_RELEASE

cat > "$brew_bin/brew" <<'FAKE_BREW'
#!/usr/bin/env bash
set -euo pipefail
printf 'brew %s\n' "$*" >> "$HOME/bootstrap-package-actions.log"
FAKE_BREW
chmod +x "$brew_bin/brew"
touch "$tmp_home/bootstrap-package-actions.log"

for tool in dnf rpm-ostree; do
    cat > "$fake_bin/$tool" <<'FAKE_LAYERING_TOOL'
#!/usr/bin/env bash
set -euo pipefail
printf 'unexpected layered package tool: %s\n' "$0" >&2
exit 1
FAKE_LAYERING_TOOL
    chmod +x "$fake_bin/$tool"
done

PATH="$fake_bin:/usr/bin:/bin" \
HOME="$tmp_home" \
AI_CLI_OS_RELEASE="$tmp_home/os-release" \
bash "$repo_root/bootstrap.sh" > "$tmp_home/output.txt"

if grep -Eq 'rpm-ostree|dnf' "$tmp_home/bootstrap-package-actions.log" "$tmp_home/output.txt"; then
    echo "Bazzite bootstrap attempted layered/system package tooling" >&2
    exit 1
fi

if ! grep -q 'using bazzite' "$tmp_home/output.txt"; then
    echo "Bazzite bootstrap branch was not used" >&2
    exit 1
fi

printf 'bazzite bootstrap brew regression passed\n'
