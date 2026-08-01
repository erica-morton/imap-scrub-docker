#!/usr/bin/env bash
# Trigger a one-off run of the task, outside the weekly schedule.
# DRY RUN by default; pass -y to actually perform the configured actions.
set -euo pipefail

cd "$(dirname "$0")/../terraform"

NAME="${NAME:-imap-scrub}"

if ! RUN_CMD="$(terraform output -raw run_now_command 2>/dev/null)"; then
    echo "error: terraform outputs unavailable — run scripts/bootstrap-state.sh first" >&2
    exit 1
fi

# Override the container command with this script's args. --dry-run is
# stripped by the entrypoint; it keeps the override non-empty so it always
# replaces the task definition's default "-y".
[ "$#" -gt 0 ] || set -- --dry-run
CMD_JSON="$(printf '"%s",' "$@")"
CMD_JSON="[${CMD_JSON%,}]"
OVERRIDES="{\"containerOverrides\":[{\"name\":\"${NAME}\",\"command\":${CMD_JSON}}]}"

eval "${RUN_CMD} \
    --overrides '${OVERRIDES}' \
    --query 'tasks[0].taskArn' --output text"

echo "Task started (imap-scrub args: $*); follow logs with:"
echo "  aws logs tail $(terraform output -raw log_group_name) --follow"
