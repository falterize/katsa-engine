#!/bin/bash
# Runs the regression suites on the dev host with the examples project mounted and fails when any
# suite fails. Run from the engine folder:  KATSA_PROJECT=<examples> tools/ci/runSuites.sh
suites=(--test-v106.8 --test-v108.10 --test-v108.9 --test-v108.7 --test-v108.5 --test-v108.4 --test-v108.1)
failed=0
for suite in "${suites[@]}"; do
    echo "== $suite"
    result="$(tools/dev/runTests.sh "$suite" 1500 | tee /dev/stderr | head -n 1)"
    case "$result" in
        *"failed: 0  exit: 0"*) ;;
        *) echo "::error title=$suite failed::$result"; failed=1 ;;
    esac
done
exit "$failed"
