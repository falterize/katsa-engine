#!/bin/sh
# Runs one engine test flag on the dev katsa host under Xvfb and prints a summary.
#   tools/dev/runTests.sh --test-v108.1 [timeoutSeconds]
flag="${1:---test}"
limit="${2:-300}"
log="${KATSA_LOG:-/tmp/katsa-$flag.log}"
# Many suites build the example scenes: run them with the examples project mounted.
project="${KATSA_PROJECT:-../katsa-engine-examples}"
[ -d "$project" ] || project=.
timeout "$limit" xvfb-run -a luajit tools/dev/katsa.lua "$project" "$flag" > "$log" 2>&1
status=$?
printf 'passed: %s  failed: %s  exit: %s  log: %s\n' "$(grep -c '^PASS' "$log")" "$(grep -c '^FAIL' "$log")" "$status" "$log"
grep -m5 -E '^FAIL|Error|error:' "$log" | cut -c1-240
