# Assignment 3 – CI/CD with GitHub Actions

## Description

This assignment implements a complete **CI/CD pipeline** using GitHub Actions for a Bash-based DevOps utility tool. The pipeline enforces a sequential quality gate:

```
validate (lint) → test (unit tests) → docker (build & smoke test)
```

Each stage must pass before the next one runs, ensuring code quality at every step.

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| `bash` 4.0+ | Running scripts locally |
| `Docker` | Building and running the containerised app |
| `Git` | Version control |
| GitHub account | Running GitHub Actions CI |

---

## Setup Instructions

```bash
# Clone your fork / push this folder to a new GitHub repository
git init
git remote add origin https://github.com/<your-username>/<your-repo>.git

# Make scripts executable
chmod +x app/app.sh scripts/lint.sh scripts/build.sh tests/test.sh grade.sh

# Push to trigger CI
git add .
git commit -m "feat: initial assignment-3 setup"
git push -u origin main
```

---

## Usage

### Running the app locally

```bash
# Show help
./app/app.sh help

# Display system information
./app/app.sh system-info

# Check if a host is reachable
./app/app.sh check-host google.com
./app/app.sh check-host localhost

# Check if a TCP port is open
./app/app.sh check-port google.com 443
./app/app.sh check-port localhost 22
```

### Exit Codes

| Code | Meaning |
|------|---------|
| `0`  | Success |
| `1`  | Runtime/operational failure (host unreachable, port closed) |
| `2`  | Invalid command or missing/invalid argument |

### Running via Docker

```bash
# Build the image
docker build -t devops-ci-tool .

# Run commands
docker run --rm devops-ci-tool help
docker run --rm devops-ci-tool system-info
docker run --rm devops-ci-tool check-host google.com
docker run --rm devops-ci-tool check-port google.com 443

# Using Docker Compose
docker compose run --rm app system-info
docker compose run --rm app check-host localhost
```

---

## CI Pipeline

The pipeline is defined in [`.github/workflows/ci.yml`](.github/workflows/ci.yml) and runs on every push and pull request to any branch.

```
┌─────────────┐     ┌──────────┐     ┌──────────┐
│  validate   │────▶│   test   │────▶│  docker  │
│             │     │          │     │          │
│ • lint.sh   │     │ • test.sh│     │ • build  │
│ • bash -n   │     │ 10 tests │     │ • smoke  │
│ • shellcheck│     │          │     │   tests  │
└─────────────┘     └──────────┘     └──────────┘
```

### Job Details

| Job | Runner | Depends On | What It Does |
|-----|--------|-----------|--------------|
| `validate` | ubuntu-latest | — | Checks file existence, bash syntax, optional shellcheck |
| `test` | ubuntu-latest | `validate` | Runs 10 unit tests against app.sh |
| `docker` | ubuntu-latest | `test` | Builds the Alpine Docker image, runs 3 smoke tests |

---

## CI Failure Demonstration

To demonstrate the CI pipeline catching real errors:

1. **Create a failure branch:**
   ```bash
   git checkout -b ci/failure-demo
   ```

2. **Introduce an intentional bug** (e.g., change `exit 2` to `exit 0` for unknown commands in `app/app.sh`):
   ```bash
   # Edit app/app.sh — break the unknown-command handler
   git add app/app.sh
   git commit -m "demo: intentional bug — unknown command exits 0 instead of 2"
   git push origin ci/failure-demo
   ```

3. **Observe the CI failure** — the `test` job fails because Test 4 (`unknown-command → exit 2`) now receives `exit 0`.

4. **Fix the bug and push:**
   ```bash
   git revert HEAD
   git push origin ci/failure-demo
   ```

5. **CI goes green** — all three jobs pass again.

---

## Testing

### Run tests locally

```bash
# Make sure app.sh is executable first
chmod +x app/app.sh

# Run the full test suite
./tests/test.sh
```

### Run tests via CI

Push any commit or open a pull request — GitHub Actions automatically runs:
1. `validate` job → `./scripts/lint.sh`
2. `test` job → `./tests/test.sh`
3. `docker` job → `./scripts/build.sh`

---

## Grading

```bash
# Make grade.sh executable and run it from the assignment-3 root
chmod +x grade.sh
./grade.sh
```

The grader checks:
- ✅ All required files exist
- ✅ Bash syntax is valid on all `.sh` files
- ✅ Scripts are marked executable
- ✅ `ci.yml` has correct job names and trigger events
- ✅ `test → validate` and `docker → test` dependency chain
- ✅ `app.sh` exit codes for all command variants
- ✅ `lint.sh` passes
- ✅ Docker image builds and smoke tests pass
- ✅ All 10 unit tests pass
- ✅ Git has ≥ 5 commits and a non-main working branch

---

## Assumptions

- Scripts are run from the `assignment-3/` root directory.
- `check-host localhost` always exits `0`; ICMP ping failures on localhost are treated as informational if ping is unavailable.
- `check-port` validates port numbers strictly: must be an integer in the range `[1, 65535]`.
- The Docker build requires internet access to pull the `alpine:3.19` base image.
- `shellcheck` linting is optional — the CI pipeline does not fail if it is not installed.
- Git checks in `grade.sh` assume the repository has been initialised and at least one commit exists.
