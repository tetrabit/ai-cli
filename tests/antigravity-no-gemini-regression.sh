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

for file in ai.sh ai.ps1; do
    check_absent "$file" '\.gemini|oauth_creds\.json' 'Gemini CLI credential reads'
    check_absent "$file" 'get_oauth_credentials|oauth2\.googleapis\.com/token' 'Gemini OAuth scraping or token refresh'
    check_absent "$file" 'cloudcode-pa\.googleapis\.com|loadCodeAssist|retrieveUserQuota' 'Google Cloud Code quota endpoints'
    check_absent "$file" 'pluginType[[:space:]]*["'\'']?:[[:space:]]*["'\'']GEMINI["'\'']' 'pluginType: GEMINI'
done

if (( failures > 0 )); then
    printf '\nAntigravity usage must stay guidance-only because ai-cli has no supported noninteractive Antigravity quota API.\n' >&2
    printf 'Implementation tasks must use td handoff, then td review, and approval must come from a separate reviewer outside the implementing session.\n' >&2
    exit 1
fi

printf 'Antigravity no-Gemini regression guard passed\n'
