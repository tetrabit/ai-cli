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
    check_absent "$file" '\.gemini|oauth_creds\.json|@google/gemini-cli' 'Gemini CLI credential reads'
    check_absent "$file" 'get_oauth_credentials|oauth2\.googleapis\.com/token' 'Gemini OAuth scraping or token refresh'
    check_absent "$file" 'no supported noninteractive Antigravity quota API|Check Antigravity settings for quota' 'rejected guidance-only Antigravity wording'
done

if (( failures > 0 )); then
    printf '\nAntigravity usage must use Antigravity-owned auth/quota evidence without Gemini CLI credential scraping.\n' >&2
    printf 'Implementation tasks must use td handoff, then td review, and approval must come from a separate reviewer outside the implementing session.\n' >&2
    exit 1
fi

if ! grep -Eq 'secret-tool", "lookup", "service", "gemini", "username", "antigravity"|service", "gemini", "username", "antigravity"' "$repo_root/ai.sh"; then
    printf 'Antigravity Bash usage no longer reads the Antigravity keyring item\n' >&2
    exit 1
fi

if ! grep -q 'daily-cloudcode-pa.googleapis.com' "$repo_root/ai.sh"; then
    printf 'Antigravity Bash usage no longer targets the current Antigravity quota host\n' >&2
    exit 1
fi

printf 'Antigravity quota regression guard passed\n'
