#!/bin/sh
# Writes the config from $IMAP_SCRUB_CONFIG (if set) to a file, then runs
# imap-scrub against it. Extra arguments are passed through, so e.g.
# `docker run <image> -y` runs `imap-scrub -y <config>`.
set -eu

CONFIG_PATH="${IMAP_SCRUB_CONFIG_PATH:-/config/imap-scrub.yml}"

if [ -n "${IMAP_SCRUB_CONFIG:-}" ]; then
    umask 077
    printf '%s\n' "$IMAP_SCRUB_CONFIG" > "$CONFIG_PATH"
fi

if [ ! -f "$CONFIG_PATH" ]; then
    echo "error: no config at $CONFIG_PATH — set IMAP_SCRUB_CONFIG or mount a config file" >&2
    exit 1
fi

exec /app/imap-scrub "$@" "$CONFIG_PATH"
