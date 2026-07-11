#!/usr/bin/env bash
#
# mayhem/test.sh — Run librdkafka internal unit tests (built by build.sh).
#
# Anti-reward-hack oracle: /mayhem/run_tests calls rd_kafka_unittest() which
# runs ~15+ internal assertion tests (data structures, hash functions, buffer
# semantics, config parsing, etc.) — all offline/broker-less. If the binary is
# neutered to exit(0), it produces no PASS output → 0 tests detected → FAIL.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# build.sh outputs the runner to /mayhem/run_tests
RUNNER="/mayhem/run_tests"

if [ ! -x "$RUNNER" ]; then
    echo "ERROR: $RUNNER not found — build.sh should have produced it" >&2
    exit 1
fi

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
    local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
    local tests=$(( passed + failed + skipped + pending + other ))
    local report="${CTRF_REPORT:-${SRC:-/mayhem}/ctrf-report.json}"
    cat > "$report" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
    printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
        "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
    [ "$failed" -eq 0 ]
}

# Run the test runner; capture stderr (RD_UT_SAY writes there)
output=$("$RUNNER" 2>&1) || true
exit_code=$?

# Strip ANSI color codes before counting — librdkafka's RD_UT_SAY embeds them:
# "unittest: NAME: \033[32mPASS\033[0m"
clean=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g')

# Count PASS/FAIL in the cleaned output
passed=$(printf '%s\n' "$clean" | grep -cE "unittest:.*PASS$" || true)
failed=$(printf '%s\n' "$clean" | grep -cE "unittest:.*FAIL$" || true)
total=$(( passed + failed ))

echo "[test.sh] Unit test results: passed=$passed failed=$failed total=$total" >&2
printf '%s\n' "$clean" | grep -E "unittest:|UNIT_TEST_SUMMARY" >&2 || true

# Anti-neutering: a neutered binary exits 0 with no output → total=0 → FAIL
if [ "$total" -eq 0 ]; then
    echo "ERROR: No unit tests counted — binary may be neutered to exit(0)" >&2
    emit_ctrf "librdkafka-unittest" 0 1 0
    exit 1
fi

# Honor runner exit code too
if [ "$exit_code" -ne 0 ] && [ "$failed" -eq 0 ]; then
    failed=1
fi

emit_ctrf "librdkafka-unittest" "$passed" "$failed" 0
