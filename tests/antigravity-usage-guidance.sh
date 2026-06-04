#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_home"
}
trap cleanup EXIT

fake_bin="$tmp_home/bin"
mkdir -p "$fake_bin"

cat > "$fake_bin/agy" <<'FAKE_AGY'
#!/usr/bin/env bash
set -euo pipefail
printf 'agy should not be invoked when AI_CLI_ANTIGRAVITY_USAGE_TEXT is set\n' >&2
exit 1
FAKE_AGY
chmod +x "$fake_bin/agy"

cat > "$fake_bin/tmux" <<'FAKE_TMUX'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    new-session)
        : > "$HOME/tmux-capture-count"
        ;;
    send-keys)
        printf '%s\n' "$*" > "$HOME/tmux-send-keys"
        ;;
    capture-pane)
        count=0
        if [[ -f "$HOME/tmux-capture-count" ]]; then
            count="$(cat "$HOME/tmux-capture-count")"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" > "$HOME/tmux-capture-count"
        if (( count == 1 )); then
            printf '>\n'
        else
            cat "$HOME/tmux-usage-fixture"
        fi
        ;;
    kill-session)
        ;;
    *)
        printf 'unexpected tmux command: %s\n' "$*" >&2
        exit 1
        ;;
esac
FAKE_TMUX
chmod +x "$fake_bin/tmux"

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

    (
        export PATH="$path"
        export HOME="$tmp_home"
        export AI_CLI_CONFIG="$config"
        for name in \
            AI_CLI_ANTIGRAVITY_USAGE_TEXT \
            AI_CLI_ANTIGRAVITY_PROMPT_TIMEOUT \
            AI_CLI_ANTIGRAVITY_USAGE_TIMEOUT \
            AI_CLI_ANTIGRAVITY_POLL_INTERVAL; do
            if [[ -n "${!name:-}" ]]; then
                export "$name"
            fi
        done
        bash "$repo_root/ai.sh" usage > "$output"
    )
}

usage_fixture="$(
    cat <<'USAGE'
└ Model Quota

  Gemini 3.5 Flash (Medium)
  bars 40%
  40% remaining · Refreshes in 4h 42m

  Gemini 3.5 Flash (High)
  bars 0%
  Refreshes in 24m

  Gemini 3.5 Flash (Low)
  bars 0%
  Refreshes in 24m

  Gemini 3.1 Pro (Low)
  bars 0%
  Refreshes in 24m

  Gemini 3.1 Pro (High)
  bars 0%
  Refreshes in 24m

  Claude Sonnet 4.6 (Thinking)
  bars 100%
  Quota available
  Refreshes in 4h 42m

  Claude Opus 4.6 (Thinking)
  bars 100%
  Quota available

  GPT-OSS 120B (Medium)
  bars 100%
  Quota available
USAGE
)"
printf '%s\n' "$usage_fixture" > "$tmp_home/tmux-usage-fixture"

tmux_config="$tmp_home/tmux-config"
tmux_output="$tmp_home/tmux-output.txt"
write_config "$tmux_config" "USAGE_ANTIGRAVITY=1"
AI_CLI_ANTIGRAVITY_PROMPT_TIMEOUT="1" \
AI_CLI_ANTIGRAVITY_USAGE_TIMEOUT="1" \
AI_CLI_ANTIGRAVITY_POLL_INTERVAL="0.01" \
run_usage "$tmux_config" "$fake_bin:/usr/bin:/bin" "$tmux_output"

if ! grep -q 'Gemini 3.5 Flash (Medium).*40.0% left  resets in 4h 42m' "$tmux_output"; then
    echo "Antigravity tmux capture did not parse the /usage refresh row" >&2
    exit 1
fi

if ! grep -q '/usage' "$tmp_home/tmux-send-keys"; then
    echo "Antigravity tmux capture did not send /usage" >&2
    exit 1
fi

enabled_config="$tmp_home/enabled-config"
enabled_output="$tmp_home/enabled-output.txt"
write_config "$enabled_config" "USAGE_ANTIGRAVITY=1"
AI_CLI_ANTIGRAVITY_USAGE_TEXT="$usage_fixture" \
run_usage "$enabled_config" "$fake_bin:/usr/bin:/bin" "$enabled_output"

if ! grep -q '==> Antigravity CLI' "$enabled_output"; then
    echo "Antigravity header was not printed when usage is enabled" >&2
    exit 1
fi

if ! grep -q 'Gemini 3.5 Flash (Medium).*40.0% left  resets in 4h 42m' "$enabled_output"; then
    echo "Antigravity did not parse the real /usage mixed percent and refresh row" >&2
    exit 1
fi

if ! grep -q 'Claude Sonnet 4.6 (Thinking).*100.0% left' "$enabled_output"; then
    echo "Antigravity did not parse the real /usage quota-available row" >&2
    exit 1
fi

if ! grep -q 'Claude Sonnet 4.6 (Thinking).*100.0% left  resets in 4h 42m' "$enabled_output"; then
    echo "Antigravity did not preserve refresh metadata for a nonempty row" >&2
    exit 1
fi

if grep -q 'no supported noninteractive Antigravity quota API' "$enabled_output"; then
    echo "Antigravity regressed to the rejected no-API guidance" >&2
    exit 1
fi

if grep -q 'Check Antigravity settings' "$enabled_output"; then
    echo "Antigravity regressed to settings-only guidance" >&2
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
AI_CLI_ANTIGRAVITY_USAGE_TEXT="$usage_fixture" \
run_usage "$legacy_disabled_config" "$fake_bin:/usr/bin:/bin" "$legacy_disabled_output"

if ! grep -q '==> Antigravity CLI' "$legacy_disabled_output"; then
    echo "Legacy USAGE_GEMINI disabled Antigravity when USAGE_ANTIGRAVITY was absent" >&2
    exit 1
fi

if ! grep -q 'Gemini 3.5 Flash (Medium).*40.0% left  resets in 4h 42m' "$legacy_disabled_output"; then
    echo "Antigravity did not use its own default enablement without USAGE_ANTIGRAVITY" >&2
    exit 1
fi

printf 'antigravity usage regression passed\n'
