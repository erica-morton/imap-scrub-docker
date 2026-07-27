#!/usr/bin/env bash
# Validate the local imap-scrub config and push it to the Secrets Manager
# secret the scheduled task reads. The new value is picked up automatically
# on the next run — no redeploy needed.
#
# Usage: scripts/push-config.sh [config.yml]   (default: imap-scrub.yml)
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-imap-scrub.yml}"
NAME="${NAME:-imap-scrub}"
SECRET_ID="${SECRET_ID:-${NAME}/config}"

if [ ! -f "$CONFIG" ]; then
    echo "error: $CONFIG not found — copy imap-scrub.example.yml to imap-scrub.yml and edit it" >&2
    exit 1
fi

case "$(basename "$CONFIG")" in
    *.example.yml)
        echo "error: refusing to push the example config" >&2
        exit 1
        ;;
esac

CONFIG_ABS="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"

# Validate by having imap-scrub itself parse and print it (password is masked)
if docker info >/dev/null 2>&1; then
    echo "--- Parsed config (as imap-scrub sees it) ---"
    docker build -q -t "$NAME" . >/dev/null
    docker run --rm -v "${CONFIG_ABS}:/config/imap-scrub.yml:ro" "$NAME" -p
    echo "---------------------------------------------"
else
    echo "warning: docker unavailable — pushing without validating the config" >&2
fi

VERSION_ID="$(aws secretsmanager put-secret-value \
    --secret-id "$SECRET_ID" \
    --secret-string "file://${CONFIG_ABS}" \
    --query VersionId --output text)"

echo "Pushed ${CONFIG} to secret ${SECRET_ID} (version ${VERSION_ID})"
echo "Test it with scripts/run-now.sh (dry run)"
