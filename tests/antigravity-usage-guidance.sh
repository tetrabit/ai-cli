#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

fake_bin="$tmp_home/bin"
mkdir -p "$fake_bin"

cat > "$fake_bin/agy" <<'FAKE_AGY'
#!/usr/bin/env bash
set -euo pipefail
printf 'agy should not be invoked\n' >&2
exit 1
FAKE_AGY
chmod +x "$fake_bin/agy"

write_config() {
    local config="$1"
    shift

    {
        printf 'USAGE_CLAUDE=0\n'
        printf 'USAGE_CODEX=0\n'
        printf 'USAGE_COPILOT=0\n'
        for line in "$@"; do
            printf '%s\n' "$line"
        done
    } > "$config"
}

run_usage() {
    local config="$1"
    local path="$2"
    local output="$3"

    PATH="$path" \
    HOME="$tmp_home" \
    AI_CLI_CONFIG="$config" \
    bash "$repo_root/ai.sh" usage > "$output"
}

enabled_config="$tmp_home/enabled-config"
enabled_output="$tmp_home/enabled-output.txt"
write_config "$enabled_config" "USAGE_ANTIGRAVITY=1"
run_usage "$enabled_config" "$fake_bin:/usr/bin:/bin" "$enabled_output"

if ! grep -q '==> Antigravity CLI' "$enabled_output"; then
    echo "Antigravity header was not printed when usage is enabled" >&2
    exit 1
fi

if ! grep -q 'no supported noninteractive Antigravity quota API' "$enabled_output"; then
    echo "Antigravity guidance did not explain the unsupported quota API" >&2
    exit 1
fi

if ! grep -q 'Check Antigravity settings' "$enabled_output"; then
    echo "Antigravity guidance did not point to settings" >&2
    exit 1
fi

if grep -q '/usage' "$enabled_output"; then
    echo "Antigravity guidance still points users to /usage" >&2
    exit 1
fi

missing_config="$tmp_home/missing-config"
missing_output="$tmp_home/missing-output.txt"
write_config "$missing_config" "USAGE_ANTIGRAVITY=1"
run_usage "$missing_config" "/usr/bin:/bin" "$missing_output"

if ! grep -q 'Usage unavailable (Antigravity CLI not installed)' "$missing_output"; then
    echo "Missing agy did not report the expected unavailable message" >&2
    exit 1
fi

disabled_config="$tmp_home/disabled-config"
disabled_output="$tmp_home/disabled-output.txt"
write_config "$disabled_config" "USAGE_GEMINI=1" "USAGE_ANTIGRAVITY=0"
run_usage "$disabled_config" "$fake_bin:/usr/bin:/bin" "$disabled_output"

if grep -q '==> Antigravity CLI' "$disabled_output"; then
    echo "Legacy USAGE_GEMINI enabled Antigravity despite USAGE_ANTIGRAVITY=0" >&2
    exit 1
fi

if ! grep -q 'No usage providers selected' "$disabled_output"; then
    echo "Disabled Antigravity did not leave usage with no selected providers" >&2
    exit 1
fi

legacy_disabled_config="$tmp_home/legacy-disabled-config"
legacy_disabled_output="$tmp_home/legacy-disabled-output.txt"
write_config "$legacy_disabled_config" "USAGE_GEMINI=0"
run_usage "$legacy_disabled_config" "$fake_bin:/usr/bin:/bin" "$legacy_disabled_output"

if ! grep -q '==> Antigravity CLI' "$legacy_disabled_output"; then
    echo "Legacy USAGE_GEMINI disabled Antigravity when USAGE_ANTIGRAVITY was absent" >&2
    exit 1
fi

if ! grep -q 'no supported noninteractive Antigravity quota API' "$legacy_disabled_output"; then
    echo "Antigravity did not use its own default enablement without USAGE_ANTIGRAVITY" >&2
    exit 1
fi

printf 'antigravity usage guidance regression passed\n'
