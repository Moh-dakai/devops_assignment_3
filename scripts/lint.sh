#!/usr/bin/env bash
# =============================================================================
# lint.sh — Static analysis and file existence checks
#
# Checks:
#   1. Required files exist
#   2. Bash syntax check (bash -n) on all .sh files
#   3. shellcheck (optional, skipped if not installed)
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed
# =============================================================================

# Do NOT use set -e so we can accumulate failures and report all of them.
set -uo pipefail

PASS=0
FAIL=1
failures=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; ((failures++)) || true; }
section() { echo; echo ">>> $*"; echo "$(printf '%0.s-' {1..60})"; }

# ---------------------------------------------------------------------------
# 1. Required file existence checks
# ---------------------------------------------------------------------------
section "Checking required files exist"

REQUIRED_FILES=(
    "README.md"
    "app/app.sh"
    "scripts/lint.sh"
    "scripts/build.sh"
    "tests/test.sh"
    "Dockerfile"
    "compose.yaml"
    ".dockerignore"
    ".github/workflows/ci.yml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        pass "File exists: $file"
    else
        fail "File missing: $file"
    fi
done

# ---------------------------------------------------------------------------
# 2. Bash syntax check on all .sh files
# ---------------------------------------------------------------------------
section "Running bash -n syntax checks on .sh files"

SHELL_DIRS=("app" "scripts" "tests")
shell_files_found=0

for dir in "${SHELL_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        while IFS= read -r -d '' script; do
            shell_files_found=1
            if bash -n "$script" 2>/tmp/bash_syntax_err; then
                pass "Syntax OK: $script"
            else
                fail "Syntax ERROR: $script"
                cat /tmp/bash_syntax_err >&2
            fi
        done < <(find "$dir" -name "*.sh" -print0 2>/dev/null)
    fi
done

if [ "$shell_files_found" -eq 0 ]; then
    fail "No .sh files found in app/, scripts/, or tests/"
fi

# ---------------------------------------------------------------------------
# 3. shellcheck (optional)
# ---------------------------------------------------------------------------
section "Running shellcheck (optional)"

if command -v shellcheck >/dev/null 2>&1; then
    echo "shellcheck found at: $(command -v shellcheck)"
    sc_failures=0
    for dir in "${SHELL_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            while IFS= read -r -d '' script; do
                if shellcheck --shell=bash --severity=warning "$script" 2>/tmp/sc_err; then
                    pass "shellcheck OK: $script"
                else
                    fail "shellcheck WARNING/ERROR: $script"
                    cat /tmp/sc_err >&2
                    ((sc_failures++)) || true
                fi
            done < <(find "$dir" -name "*.sh" -print0 2>/dev/null)
        fi
    done
else
    echo "shellcheck not installed — skipping (install with: apt-get install shellcheck)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section "Lint Summary"

if [ "$failures" -eq 0 ]; then
    echo "[PASS] All lint checks passed!"
    exit 0
else
    echo "[FAIL] $failures check(s) failed."
    exit 1
fi
