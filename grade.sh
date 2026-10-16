#!/usr/bin/env bash
# =============================================================================
# grade.sh — Automated grading script for Assignment 3: CI/CD with GitHub Actions
#
# Checks performed:
#   1.  Required files exist
#   2.  Bash syntax (bash -n) on all .sh files
#   3.  Executable permissions on key scripts
#   4.  ci.yml contains required job names and trigger events
#   5.  Job dependency chain (needs: validate, needs: test)
#   6.  app.sh behaviour: exit code correctness
#   7.  lint.sh runs successfully
#   8.  Docker build + smoke tests (if Docker available)
#   9.  tests/test.sh passes
#   10. Git checks (≥5 commits, non-main branch)
#
# NOTE: set -e is intentionally NOT used so all checks run regardless of failures.
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# Scoring state
# ---------------------------------------------------------------------------
total_points=0
earned_points=0
declare -a failures=()
declare -a passes=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
section() {
    echo
    echo "############################################################"
    echo "#  $*"
    echo "############################################################"
}

award() {
    local points="$1"
    local name="$2"
    echo "[PASS +${points}pt] $name"
    ((earned_points += points)) || true
    ((total_points += points)) || true
    passes+=("$name")
}

deduct() {
    local points="$1"
    local name="$2"
    echo "[FAIL  -${points}pt] $name"
    ((total_points += points)) || true
    failures+=("$name")
}

check_file_exists() {
    local file="$1"
    local points="${2:-5}"
    if [ -f "$file" ]; then
        award "$points" "File exists: $file"
    else
        deduct "$points" "File missing: $file"
    fi
}

check_executable() {
    local file="$1"
    local points="${2:-2}"
    if [ -x "$file" ]; then
        award "$points" "Executable: $file"
    else
        deduct "$points" "Not executable: $file"
    fi
}

# ---------------------------------------------------------------------------
# 1. Required files
# ---------------------------------------------------------------------------
section "1. Required File Checks"

REQUIRED=(
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

for f in "${REQUIRED[@]}"; do
    check_file_exists "$f" 5
done

# ---------------------------------------------------------------------------
# 2. Bash syntax checks
# ---------------------------------------------------------------------------
section "2. Bash Syntax Checks (bash -n)"

SHELL_DIRS=("app" "scripts" "tests")
syntax_ok=1

for dir in "${SHELL_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        while IFS= read -r -d '' script; do
            if bash -n "$script" 2>/tmp/grade_syntax_err; then
                award 3 "Syntax OK: $script"
            else
                deduct 3 "Syntax ERROR: $script"
                cat /tmp/grade_syntax_err
                syntax_ok=0
            fi
        done < <(find "$dir" -name "*.sh" -print0 2>/dev/null)
    fi
done

# ---------------------------------------------------------------------------
# 3. Executable permissions
# ---------------------------------------------------------------------------
section "3. Executable Permission Checks"

EXECUTABLES=(
    "app/app.sh"
    "scripts/lint.sh"
    "scripts/build.sh"
    "tests/test.sh"
)

for f in "${EXECUTABLES[@]}"; do
    check_executable "$f" 2
done

# ---------------------------------------------------------------------------
# 4. ci.yml content: required keywords
# ---------------------------------------------------------------------------
section "4. ci.yml Content Checks"

CI_FILE=".github/workflows/ci.yml"

if [ -f "$CI_FILE" ]; then
    ci_keywords=("push:" "pull_request:" "validate:" "test:" "docker:")
    for kw in "${ci_keywords[@]}"; do
        if grep -q "$kw" "$CI_FILE"; then
            award 3 "ci.yml contains '$kw'"
        else
            deduct 3 "ci.yml missing '$kw'"
        fi
    done

    # 5. Job dependency chain
    section "5. ci.yml Job Dependency Chain"

    if grep -q 'needs:.*validate\|needs:\s*\[.*validate' "$CI_FILE" || \
       grep -A5 'test:' "$CI_FILE" | grep -q 'needs:'; then
        award 5 "'test' job has needs dependency (validate)"
    else
        deduct 5 "'test' job missing 'needs: validate'"
    fi

    if grep -q 'needs:.*test\|needs:\s*\[.*test' "$CI_FILE" || \
       grep -A5 'docker:' "$CI_FILE" | grep -q 'needs:'; then
        award 5 "'docker' job has needs dependency (test)"
    else
        deduct 5 "'docker' job missing 'needs: test'"
    fi
else
    deduct 15 "ci.yml not found — skipping content checks"
fi

# ---------------------------------------------------------------------------
# 6. app.sh behaviour tests
# ---------------------------------------------------------------------------
section "6. app.sh Behaviour Tests"

APP="./app/app.sh"

if [ -f "$APP" ]; then
    # Ensure executable
    chmod +x "$APP" 2>/dev/null || true

    run_app_test() {
        local test_name="$1"
        local expected_exit="$2"
        shift 2
        local actual_exit=0
        "$APP" "$@" >/dev/null 2>&1 || actual_exit=$?
        if [ "$actual_exit" -eq "$expected_exit" ]; then
            award 5 "app.sh $test_name → exit $actual_exit (expected $expected_exit)"
        else
            deduct 5 "app.sh $test_name → exit $actual_exit (expected $expected_exit)"
        fi
    }

    run_app_test "help"                              0  help
    run_app_test "system-info"                       0  system-info
    run_app_test "(no args)"                         2
    run_app_test "invalid-cmd"                       2  invalid-cmd
    run_app_test "check-port localhost abc"          2  check-port localhost abc
    run_app_test "check-port localhost 0"            2  check-port localhost 0
    run_app_test "check-port localhost 65536"        2  check-port localhost 65536
else
    deduct 35 "app/app.sh not found — skipping behaviour tests"
fi

# ---------------------------------------------------------------------------
# 7. Run lint.sh
# ---------------------------------------------------------------------------
section "7. Running lint.sh"

if [ -x "./scripts/lint.sh" ]; then
    if ./scripts/lint.sh; then
        award 10 "lint.sh passed"
    else
        deduct 10 "lint.sh reported failures"
    fi
else
    deduct 10 "scripts/lint.sh not executable or not found"
fi

# ---------------------------------------------------------------------------
# 8. Docker build and smoke tests
# ---------------------------------------------------------------------------
section "8. Docker Build & Smoke Tests"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "Docker is available — running build and smoke tests"

    if docker build -t devops-ci-tool-grade . >/tmp/grade_docker_build.log 2>&1; then
        award 10 "Docker image built successfully"

        # Smoke test: help → exit 0
        docker run --rm devops-ci-tool-grade help >/dev/null 2>&1
        code=$?
        if [ "$code" -eq 0 ]; then
            award 5 "Docker smoke test: help → exit 0"
        else
            deduct 5 "Docker smoke test: help → exit $code (expected 0)"
        fi

        # Smoke test: system-info → exit 0
        docker run --rm devops-ci-tool-grade system-info >/dev/null 2>&1
        code=$?
        if [ "$code" -eq 0 ]; then
            award 5 "Docker smoke test: system-info → exit 0"
        else
            deduct 5 "Docker smoke test: system-info → exit $code (expected 0)"
        fi

        # Smoke test: invalid-command → non-zero
        docker run --rm devops-ci-tool-grade invalid-command >/dev/null 2>&1
        code=$?
        if [ "$code" -ne 0 ]; then
            award 5 "Docker smoke test: invalid-command → exit $code (non-zero)"
        else
            deduct 5 "Docker smoke test: invalid-command exited 0 (expected non-zero)"
        fi

        # Cleanup
        docker rmi devops-ci-tool-grade >/dev/null 2>&1 || true
    else
        deduct 25 "Docker image build FAILED"
        cat /tmp/grade_docker_build.log >&2
    fi
else
    echo "Docker not available — skipping Docker checks (0 points awarded/deducted)"
fi

# ---------------------------------------------------------------------------
# 9. Run tests/test.sh
# ---------------------------------------------------------------------------
section "9. Running tests/test.sh"

if [ -x "./tests/test.sh" ]; then
    if ./tests/test.sh; then
        award 15 "tests/test.sh all tests passed"
    else
        deduct 15 "tests/test.sh reported failures"
    fi
else
    deduct 15 "tests/test.sh not executable or not found"
fi

# ---------------------------------------------------------------------------
# 10. Git checks
# ---------------------------------------------------------------------------
section "10. Git Repository Checks"

if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    # Commit count
    commit_count=$(git rev-list --count HEAD 2>/dev/null || echo 0)
    echo "Commit count: $commit_count"
    if [ "$commit_count" -ge 5 ]; then
        award 5 "Git: at least 5 commits ($commit_count found)"
    else
        deduct 5 "Git: fewer than 5 commits ($commit_count found, need ≥5)"
    fi

    # Non-main branch check
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    echo "Current branch: $current_branch"
    if [ "$current_branch" != "main" ] && [ "$current_branch" != "master" ]; then
        award 5 "Git: working on non-main branch ('$current_branch')"
    else
        deduct 5 "Git: should have a feature/ci-failure branch (currently on '$current_branch')"
    fi
else
    echo "Not a git repository or git not available — skipping git checks"
fi

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
section "GRADING SUMMARY"

echo
echo "Passed checks:"
for p in "${passes[@]}"; do
    echo "  ✓ $p"
done

if [ "${#failures[@]}" -gt 0 ]; then
    echo
    echo "Failed checks:"
    for f in "${failures[@]}"; do
        echo "  ✗ $f"
    done
fi

echo
echo "============================================"
echo "  Score: $earned_points / $total_points"
echo "============================================"

if [ "$earned_points" -eq "$total_points" ]; then
    echo "  PERFECT SCORE! All checks passed."
elif [ "$earned_points" -ge $((total_points * 70 / 100)) ]; then
    echo "  GOOD — above 70%."
else
    echo "  NEEDS WORK — below 70%."
fi

echo
