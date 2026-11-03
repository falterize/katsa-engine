#!/bin/bash
# Runs a command; if it fails, publishes the last lines of its output as one GitHub error annotation
# (visible on the run summary page and through the public API) and keeps the exit status.
#   tools/ci/annotate.sh "label" command args...
label="$1"
shift
log="$(mktemp)"
"$@" 2>&1 | tee "$log"
status="${PIPESTATUS[0]}"
if [ "$status" != 0 ]; then
    errors="$(grep -iE 'error|fatal|undefined|not found|cannot|failed' "$log" | head -n 12 | cut -c1-300)"
    text="$(printf '%s\n--- tail ---\n%s' "$errors" "$(grep -v '^\s*$' "$log" | tail -n 12 | cut -c1-200)")"
    text="${text//'%'/'%25'}"
    text="${text//$'\r'/}"
    text="${text//$'\n'/'%0A'}"
    echo "::error title=${label} failed (exit ${status})::${text}"
fi
exit "$status"
