#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_home="$(mktemp -d)"
server_pid=""
cleanup() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
    fi
    rm -rf "$tmp_home"
}
trap cleanup EXIT

fake_bin="$tmp_home/bin"
mkdir -p "$fake_bin"

cat > "$fake_bin/agy" <<'FAKE_AGY'
#!/usr/bin/env bash
set -euo pipefail
log_file=""
while (($#)); do
    case "$1" in
        --log-file)
            shift
            log_file="${1:-}"
            ;;
    esac
    shift || true
done
if [[ -n "$log_file" ]]; then
    printf 'OAuth: authenticated successfully as test@example.com\n' > "$log_file"
    printf 'RESOURCE_EXHAUSTED (code 429): Individual quota reached. Resets in 12m34s.\n' >> "$log_file"
fi
FAKE_AGY
chmod +x "$fake_bin/agy"

cat > "$fake_bin/secret-tool" <<'FAKE_SECRET_TOOL'
#!/usr/bin/env bash
exit 1
FAKE_SECRET_TOOL
chmod +x "$fake_bin/secret-tool"

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
        if [[ -n "${AI_CLI_ANTIGRAVITY_ACCESS_TOKEN:-}" ]]; then
            export AI_CLI_ANTIGRAVITY_ACCESS_TOKEN
        fi
        if [[ -n "${AI_CLI_ANTIGRAVITY_API_BASE:-}" ]]; then
            export AI_CLI_ANTIGRAVITY_API_BASE
        fi
        bash "$repo_root/ai.sh" usage > "$output"
    )
}

port_file="$tmp_home/api-port"
python3 - "$port_file" <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file = sys.argv[1]


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        _ = self.rfile.read(int(self.headers.get("Content-Length", "0") or "0"))
        if self.path == "/v1internal:loadCodeAssist":
            payload = {"cloudaicompanionProject": "projects/test"}
        elif self.path == "/v1internal:retrieveUserQuota":
            payload = {
                "buckets": [
                    {
                        "modelId": "gemini-2.5-flash",
                        "remainingFraction": 0.5,
                        "resetTime": "2026-06-04T12:00:00Z",
                        "tokenType": "REQUESTS",
                    },
                    {
                        "modelId": "gemini-3.1-pro-preview",
                        "remainingFraction": 1,
                        "resetTime": "2026-06-04T13:00:00Z",
                        "tokenType": "REQUESTS",
                    },
                ]
            }
        else:
            self.send_response(404)
            self.end_headers()
            return
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        return


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="utf-8") as handle:
    handle.write(str(server.server_port))
server.serve_forever()
PY
server_pid=$!

for _ in {1..50}; do
    [[ -s "$port_file" ]] && break
    sleep 0.1
done
if [[ ! -s "$port_file" ]]; then
    echo "Fake Antigravity API server did not start" >&2
    exit 1
fi

api_config="$tmp_home/api-config"
api_output="$tmp_home/api-output.txt"
write_config "$api_config" "USAGE_ANTIGRAVITY=1"
AI_CLI_ANTIGRAVITY_ACCESS_TOKEN="fake-token" \
AI_CLI_ANTIGRAVITY_API_BASE="http://127.0.0.1:$(cat "$port_file")" \
run_usage "$api_config" "$fake_bin:/usr/bin:/bin" "$api_output"

if ! grep -q 'Gemini 3.5 Flash (High).*50.0% left' "$api_output"; then
    echo "Antigravity direct quota API rows were not rendered" >&2
    exit 1
fi

if ! grep -q 'GPT-OSS 120B (Medium).*100.0% left' "$api_output"; then
    echo "Antigravity direct quota API did not render all mapped buckets" >&2
    exit 1
fi

enabled_config="$tmp_home/enabled-config"
enabled_output="$tmp_home/enabled-output.txt"
write_config "$enabled_config" "USAGE_ANTIGRAVITY=1"
run_usage "$enabled_config" "$fake_bin:/usr/bin:/bin" "$enabled_output"

if ! grep -q '==> Antigravity CLI' "$enabled_output"; then
    echo "Antigravity header was not printed when usage is enabled" >&2
    exit 1
fi

if ! grep -q 'Antigravity quota exhausted; resets in 12m34s' "$enabled_output"; then
    echo "Antigravity did not parse the CLI quota reset status" >&2
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
run_usage "$legacy_disabled_config" "$fake_bin:/usr/bin:/bin" "$legacy_disabled_output"

if ! grep -q '==> Antigravity CLI' "$legacy_disabled_output"; then
    echo "Legacy USAGE_GEMINI disabled Antigravity when USAGE_ANTIGRAVITY was absent" >&2
    exit 1
fi

if ! grep -q 'Antigravity quota exhausted; resets in 12m34s' "$legacy_disabled_output"; then
    echo "Antigravity did not use its own default enablement without USAGE_ANTIGRAVITY" >&2
    exit 1
fi

printf 'antigravity usage regression passed\n'
