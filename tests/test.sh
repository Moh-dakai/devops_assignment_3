#!/usr/bin/env bash
# =============================================================================
# test.sh — Test suite for app/app.sh
#
# Runs at least 10 meaningful tests covering exit codes and output validation.
#
# Exit codes:
#   0 — all tests passed
#   1 — one or more tests failed
# =============================================================================

set -uo pipefail

APP="./app/app.sh"
passed=0
failed=0
total=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
section() {
    echo
    echo "========================================"
    echo "  $*"
    echo "========================================"
}

# expect_exit <test_name> <expected_exit> <actual_exit>
expect_exit() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    ((total++)) || true
    if [ "$actual" -eq "$expected" ]; then
        echo "[PASS] $name (exit=$actual)"
        ((passed++)) || true
    else
        echo "[FAIL] $name — expected exit $expected, got $actual"
        ((failed++)) || true
    fi
}

# expect_output_nonempty <test_name> <output>
expect_output_nonempty() {
    local name="$1"
    local output="$2"
    ((total++)) || true
    if [ -n "$output" ]; then
        echo "[PASS] $name — output is non-empty"
        ((passed++)) || true
    else
        echo "[FAIL] $name — expected non-empty output, got empty"
        ((failed++)) || true
    fi
}

# ---------------------------------------------------------------------------
# Pre-flight: ensure app.sh is executable
# ---------------------------------------------------------------------------
if [ ! -f "$APP" ]; then
    echo "ERROR: $APP not found. Run tests from the assignment-3 root directory." >&2
    exit 1
fi

chmod +x "$APP"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

section "Test 1: help command exits 0"
"$APP" help >/dev/null 2>&1
expect_exit "help → exit 0" 0 $?

# ---------------------------------------------------------------------------
section "Test 2: system-info exits 0 and produces output"
output=$("$APP" system-info 2>&1)
exit_code=$?
expect_exit "system-info → exit 0" 0 "$exit_code"
expect_output_nonempty "system-info → non-empty output" "$output"

# ---------------------------------------------------------------------------
section "Test 3: no command → exit 2"
"$APP" >/dev/null 2>&1
expect_exit "no args → exit 2" 2 $?

# ---------------------------------------------------------------------------
section "Test 4: unknown command → exit 2"
"$APP" invalid-xyz >/dev/null 2>&1
expect_exit "unknown command 'invalid-xyz' → exit 2" 2 $?

# ---------------------------------------------------------------------------
section "Test 5: check-host with no host → exit 2"
"$APP" check-host >/dev/null 2>&1
expect_exit "check-host (missing host) → exit 2" 2 $?

# ---------------------------------------------------------------------------
section "Test 6: check-host localhost → exit 0"
"$APP" check-host localhost >/dev/null 2>&1
expect_exit "check-host localhost → exit 0" 0 $?

# ---------------------------------------------------------------------------
section "Test 7: check-port with missing port → exit 2"
"$APP" check-port localhost >/dev/null 2>&1
expect_exit "check-port localhost (missing port) → exit 2" 2 $?

# ---------------------------------------------------------------------------
section "Test 8: check-port non-numeric port → exit 2"
"$APP" check-port localhost abc >/dev/null 2>&1
expect_exit "check-port localhost abc (non-numeric) → exit 2" 2 $?

# ---------------------------------------------------------------------------
section "Test 9: check-port port 0 → exit 2 (out of range low)"
"$APP" check-port localhost 0 >/dev/null 2>&1
expect_exit "check-port localhost 0 (port ≤ 0) → exit 2" 2 $?

# ---------------------------------------------------------------------------
section "Test 10: check-port port 65536 → exit 2 (out of range high)"
"$APP" check-port localhost 65536 >/dev/null 2>&1
expect_exit "check-port localhost 65536 (port > 65535) → exit 2" 2 $?

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "========================================"
echo "  Test Summary"
echo "========================================"
echo "  Total  : $total"
echo "  Passed : $passed"
echo "  Failed : $failed"
echo "========================================"

if [ "$failed" -eq 0 ]; then
    echo "[PASS] All $passed/$total tests passed!"
    exit 0
else
    echo "[FAIL] $failed/$total test(s) failed."
    exit 1
fi
