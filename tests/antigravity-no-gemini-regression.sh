#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0

check_absent() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if grep -En -- "$pattern" "$repo_root/$file" >/tmp/ai-cli-antigravity-regression-match.$$; then
        printf 'forbidden Antigravity usage regression in %s: %s\n' "$file" "$description" >&2
        cat /tmp/ai-cli-antigravity-regression-match.$$ >&2
        failures=$((failures + 1))
    fi
    rm -f /tmp/ai-cli-antigravity-regression-match.$$
}

for file in ai.sh; do
    check_absent "$file" '\.gemini|oauth_creds\.json|@google/gemini-cli' 'Gemini CLI credential reads'
    check_absent "$file" 'get_oauth_credentials|oauth2\.googleapis\.com/token' 'Gemini OAuth scraping or token refresh'
    check_absent "$file" 'no supported noninteractive Antigravity quota API|Check Antigravity settings for quota' 'rejected guidance-only Antigravity wording'
    check_absent "$file" 'daily-cloudcode-pa\.googleapis\.com|loadCodeAssist|retrieveUserQuota|pluginType|secret-tool' 'non-usage Antigravity quota shortcut'
done

if (( failures > 0 )); then
    printf '\nAntigravity usage must use Antigravity-owned auth/quota evidence without Gemini CLI credential scraping.\n' >&2
    printf 'Implementation tasks must use td handoff, then td review, and approval must come from a separate reviewer outside the implementing session.\n' >&2
    exit 1
fi

if [[ -e "$repo_root/ai.ps1" ]]; then
    printf 'PowerShell script should not exist after Windows support removal\n' >&2
    exit 1
fi

if ! grep -q 'AI_CLI_ANTIGRAVITY_USAGE_TEXT' "$repo_root/ai.sh"; then
    printf 'Antigravity usage parser test seam is missing\n' >&2
    exit 1
fi

printf 'Antigravity /usage regression guard passed\n'
