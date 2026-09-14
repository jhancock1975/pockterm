#!/bin/bash
# Fast unit-test loop for pockterm.
#
#   scripts/test.sh --build   # recompile first (required after source changes)
#   scripts/test.sh           # re-run tests against the last build (~1 min)
#
# Read the EXIT STATUS, not the output. `scripts/test.sh | tail -5` reports
# tail's status, not the script's, so a failed run reads as a pass — that has
# already been mis-reported once.
#
# Why this exists (vs. plain `xcodebuild test`):
#   - build-for-testing/test-without-building splits the ~2-3 min compile from
#     the seconds-long test run, so iterating on tests is cheap.
#   - xcodebuild reliably wedges AFTER all tests finish on this setup (teardown
#     hang, 10+ min); we detect "every started test has a result", give
#     teardown a short grace period, then kill xcodebuild ourselves.
#   - A hung test would otherwise sit until iOS's 600 s watchdog kills the test
#     host; -default-test-execution-time-allowance fails it at ~60 s instead,
#     and our own stall detector catches whatever slips past that.
set -uo pipefail
cd "$(dirname "$0")/.."

DEST='platform=iOS Simulator,name=iPhone 17'
# SwiftTerm 1.19.0+ ships a build-tool plugin (SwiftTermBuildInfoPlugin) that
# stamps its git branch/tag/commit into a generated Swift file. Xcode refuses to
# run any package plugin non-interactively without a trust prompt, so a headless
# build fails at "Validate plug-in". This flag is the only way past it.
# The trade-off is real: it also waives validation for any FUTURE plugin any
# dependency adds, so re-read the plugin sources whenever SwiftTerm moves.
PLUGIN_FLAG='-skipPackagePluginValidation'
LOG=${TEST_LOG:-/tmp/pockterm-tests.log}
GRACE=20      # seconds to let xcodebuild exit on its own after tests finish
STALL=180     # seconds with no new results before we declare a hang

if [[ "${1:-}" == "--build" ]]; then
    echo "building for testing..."
    if ! xcodebuild build-for-testing -project pockterm.xcodeproj -scheme pockterm \
            -destination "$DEST" $PLUGIN_FLAG > /tmp/pockterm-build-for-testing.log 2>&1; then
        echo "BUILD FAILED — last 30 lines of /tmp/pockterm-build-for-testing.log:"
        tail -30 /tmp/pockterm-build-for-testing.log
        exit 65
    fi
fi

: > "$LOG"
xcodebuild test-without-building -project pockterm.xcodeproj -scheme pockterm \
    -destination "$DEST" -only-testing:pocktermTests \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 60 \
    -maximum-test-execution-time-allowance 120 \
    >> "$LOG" 2>&1 &
XCB=$!

results() { grep -cE "^[✔✘] Test .* (passed|failed) after" "$LOG" 2>/dev/null || true; }
# "(" excludes the run-level "◇ Test run started." line
started() { grep -cE "^◇ Test .*\(.*\) started\." "$LOG" 2>/dev/null || true; }

last_results=0
stall_started=$SECONDS
killed=0   # set when WE stop xcodebuild, so its status can be ignored
while true; do
    if ! kill -0 "$XCB" 2>/dev/null; then
        break   # xcodebuild exited on its own
    fi
    if grep -qE '\*\* TEST (SUCCEEDED|FAILED) \*\*' "$LOG"; then
        sleep "$GRACE"; kill "$XCB" 2>/dev/null; killed=1
        break
    fi
    r=$(results); s=$(started)
    if [[ "$r" -gt 0 && "$s" -gt 0 && "$r" -ge "$s" ]]; then
        # every started test has a result; xcodebuild is only tearing down
        sleep "$GRACE"
        kill -0 "$XCB" 2>/dev/null && { echo "(killed xcodebuild teardown hang)"; kill "$XCB" 2>/dev/null; }
        killed=1
        break
    fi
    if [[ "$r" -ne "$last_results" ]]; then
        last_results=$r; stall_started=$SECONDS
    elif (( SECONDS - stall_started > STALL )); then
        echo "STALLED: no new test results for ${STALL}s — killing run. In-flight tests:"
        # started but never finished = the hang suspects
        comm -23 <(grep -oE "^◇ Test [^ ]+ started\." "$LOG" | awk '{print $3}' | sort -u) \
                 <(grep -oE "^[✔✘] Test [^ ]+ " "$LOG" | awk '{print $3}' | sort -u)
        kill "$XCB" 2>/dev/null
        exit 70
    fi
    sleep 3
done

# Reap xcodebuild and judge its status. A kill WE issued is expected and says
# nothing — that is the teardown-hang workaround this script exists for. A
# non-zero status from a process we did not kill means the run collapsed partway,
# and the greps below cannot see that: a run that dies after one passing test
# with no ✘ line reads as green. Verified with a stub that exits 70 after two
# passes — before this check it printed TESTS GREEN.
wait "$XCB" 2>/dev/null; status=$?
if [[ "$killed" -eq 0 && "$status" -ne 0 ]]; then
    echo "RUN DID NOT FINISH — xcodebuild exited $status. Tail of log:"
    tail -20 "$LOG"
    exit 1
fi

passed=$(grep -c "^✔ Test .* passed" "$LOG" || true)
failed=$(grep -c "^✘" "$LOG" || true)
# Authoritative per-run total (per-line ✔ counts drift on parameterized tests).
grep -hE "^[✔✘] Test run with" "$LOG" || echo "passed: $passed   failed: $failed"
echo "(log: $LOG)"
if [[ "$failed" -gt 0 ]]; then
    grep -E "^✘" "$LOG" | head -20
    exit 1
fi
if [[ "$passed" -eq 0 ]]; then
    echo "NO RESULTS — tail of log:"; tail -20 "$LOG"
    exit 1
fi
echo "TESTS GREEN"
