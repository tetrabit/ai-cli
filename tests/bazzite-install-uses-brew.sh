#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

fake_bin="$tmp_home/bin"
mkdir -p "$fake_bin"

cat > "$tmp_home/os-release" <<'OS_RELEASE'
ID=bazzite
ID_LIKE=fedora
OS_RELEASE

for tool in curl git python3 gh bun just; do
    cat > "$fake_bin/$tool" <<'FAKE_COMMAND'
#!/usr/bin/env bash
set -euo pipefail
exit 0
FAKE_COMMAND
    chmod +x "$fake_bin/$tool"
done

cat > "$fake_bin/brew" <<'FAKE_BREW'
#!/usr/bin/env bash
set -euo pipefail

printf 'brew %s\n' "$*" >> "$HOME/install-package-actions.log"
if [[ "${1:-}" == "install" && "${2:-}" == "node" ]]; then
    cat > "$HOME/bin/npm" <<'FAKE_NPM'
#!/usr/bin/env bash
set -euo pipefail
exit 0
FAKE_NPM
    chmod +x "$HOME/bin/npm"
fi
FAKE_BREW
chmod +x "$fake_bin/brew"

for tool in dnf rpm-ostree sudo; do
    cat > "$fake_bin/$tool" <<'FAKE_LAYERING_TOOL'
#!/usr/bin/env bash
set -euo pipefail
printf 'unexpected system install tool: %s\n' "$0" >&2
exit 1
FAKE_LAYERING_TOOL
    chmod +x "$fake_bin/$tool"
done

PATH="$fake_bin:/usr/bin:/bin" \
HOME="$tmp_home" \
AI_CLI_OS_RELEASE="$tmp_home/os-release" \
AI_CLI_BAZZITE_BREW_BIN="$fake_bin" \
bash "$repo_root/install.sh" --local > "$tmp_home/output.txt"

if ! grep -q '^brew install node$' "$tmp_home/install-package-actions.log"; then
    echo "Bazzite installer did not use brew to install missing npm/node" >&2
    exit 1
fi

if grep -Eq 'dnf|rpm-ostree|sudo' "$tmp_home/install-package-actions.log" "$tmp_home/output.txt"; then
    echo "Bazzite installer attempted system package tooling" >&2
    exit 1
fi

if [[ ! -x "$tmp_home/.local/bin/ai" ]]; then
    echo "Bazzite installer did not install ai into ~/.local/bin" >&2
    exit 1
fi

printf 'bazzite install brew regression passed\n'
