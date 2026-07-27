#!/usr/bin/env bash
# Trigger a one-off run of the task, outside the weekly schedule.
# DRY RUN by default; pass -y to actually perform the configured actions.
set -euo pipefail

cd "$(dirname "$0")/../terraform"

NAME="${NAME:-imap-scrub}"

# Override the container command with this script's args (none = dry run)
CMD_JSON="[]"
if [ "$#" -gt 0 ]; then
    CMD_JSON="$(printf '"%s",' "$@")"
    CMD_JSON="[${CMD_JSON%,}]"
fi
OVERRIDES="{\"containerOverrides\":[{\"name\":\"${NAME}\",\"command\":${CMD_JSON}}]}"

eval "$(terraform output -raw run_now_command) \
    --overrides '${OVERRIDES}' \
    --query 'tasks[0].taskArn' --output text"

echo "Task started (imap-scrub args: ${*:-none, dry run}); follow logs with:"
echo "  aws logs tail $(terraform output -raw log_group_name) --follow"
