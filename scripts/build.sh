#!/usr/bin/env bash
# =============================================================================
# build.sh — Docker build and smoke-test script
#
# Steps:
#   1. Build the Docker image tagged devops-ci-tool
#   2. Smoke test: help command  → must exit 0
#   3. Smoke test: system-info   → must exit 0
#   4. Smoke test: invalid-command → must exit non-zero
#   5. Remove the image
#
# Exit codes:
#   0 — all steps passed
#   1 — one or more steps failed
# =============================================================================

# Do NOT use set -e so we can run all tests and report failures.
set -uo pipefail

IMAGE_NAME="devops-ci-tool"
failures=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
pass()    { echo "[PASS] $*"; }
fail()    { echo "[FAIL] $*"; ((failures++)) || true; }
section() { echo; echo ">>> $*"; echo "$(printf '%0.s-' {1..60})"; }

# ---------------------------------------------------------------------------
# Preflight: Docker available?
# ---------------------------------------------------------------------------
section "Preflight checks"

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is not installed or not in PATH." >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not running or not accessible." >&2
    exit 1
fi

pass "Docker is available and running"

# ---------------------------------------------------------------------------
# Step 1: Build the image
# ---------------------------------------------------------------------------
section "Building Docker image: $IMAGE_NAME"

if docker build -t "$IMAGE_NAME" . ; then
    pass "Docker image built successfully: $IMAGE_NAME"
else
    fail "Docker image build FAILED"
    echo "Cannot continue smoke tests without a built image." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 2: Smoke test — help
# ---------------------------------------------------------------------------
section "Smoke test: help command (expect exit 0)"

docker run --rm "$IMAGE_NAME" help
exit_code=$?
if [ "$exit_code" -eq 0 ]; then
    pass "Smoke test PASSED: 'help' exited with $exit_code"
else
    fail "Smoke test FAILED: 'help' exited with $exit_code (expected 0)"
fi

# ---------------------------------------------------------------------------
# Step 3: Smoke test — system-info
# ---------------------------------------------------------------------------
section "Smoke test: system-info command (expect exit 0)"

output=$(docker run --rm "$IMAGE_NAME" system-info 2>&1)
exit_code=$?
if [ "$exit_code" -eq 0 ]; then
    pass "Smoke test PASSED: 'system-info' exited with $exit_code"
    echo "$output"
else
    fail "Smoke test FAILED: 'system-info' exited with $exit_code (expected 0)"
    echo "$output"
fi

# ---------------------------------------------------------------------------
# Step 4: Smoke test — invalid command (must exit non-zero)
# ---------------------------------------------------------------------------
section "Smoke test: invalid-command (expect non-zero exit)"

docker run --rm "$IMAGE_NAME" invalid-command >/dev/null 2>&1
exit_code=$?
if [ "$exit_code" -ne 0 ]; then
    pass "Smoke test PASSED: 'invalid-command' exited with $exit_code (non-zero as expected)"
else
    fail "Smoke test FAILED: 'invalid-command' exited with 0 (expected non-zero)"
fi

# ---------------------------------------------------------------------------
# Step 5: Clean up image
# ---------------------------------------------------------------------------
section "Cleaning up Docker image: $IMAGE_NAME"

if docker rmi "$IMAGE_NAME" >/dev/null 2>&1; then
    pass "Image removed: $IMAGE_NAME"
else
    # Not a fatal failure — image may already be gone or in use
    echo "WARNING: Could not remove image '$IMAGE_NAME' (may already be removed or in use)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section "Build Summary"

if [ "$failures" -eq 0 ]; then
    echo "[PASS] All build and smoke tests passed!"
    exit 0
else
    echo "[FAIL] $failures step(s) failed."
    exit 1
fi
