#!/usr/bin/env bash
# =============================================================================
# app.sh — DevOps CI Tool
# A utility script for system information and network diagnostics.
#
# Usage:
#   ./app/app.sh system-info
#   ./app/app.sh check-host <host>
#   ./app/app.sh check-port <host> <port>
#   ./app/app.sh help
#
# Exit codes:
#   0 — success
#   1 — runtime/operational failure (e.g. host unreachable, port closed)
#   2 — invalid command or missing/invalid arguments
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
    cat <<'EOF'
DevOps CI Tool — app.sh

USAGE:
  ./app/app.sh <command> [arguments]

COMMANDS:
  system-info              Display hostname, OS, kernel, uptime, CPU, and memory
  check-host <host>        Resolve and ping a hostname or IP address
  check-port <host> <port> Test TCP connectivity to host:port (port: 1-65535)
  help                     Show this help message

EXIT CODES:
  0  Success
  1  Runtime / operational failure (host unreachable, port closed, etc.)
  2  Invalid command or missing / invalid argument
EOF
}

# Print an error message to stderr and exit with the given code.
die() {
    local code="$1"
    shift
    echo "ERROR: $*" >&2
    exit "$code"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_system_info() {
    echo "===== System Information ====="
    echo "Hostname : $(hostname 2>/dev/null || echo 'N/A')"

    # OS description — try several sources
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "OS       : ${PRETTY_NAME:-${NAME:-Unknown}}"
    elif command -v uname >/dev/null 2>&1; then
        echo "OS       : $(uname -s)"
    else
        echo "OS       : N/A"
    fi

    echo "Kernel   : $(uname -r 2>/dev/null || echo 'N/A')"

    # Uptime
    if command -v uptime >/dev/null 2>&1; then
        echo "Uptime   : $(uptime -p 2>/dev/null || uptime 2>/dev/null || echo 'N/A')"
    else
        echo "Uptime   : N/A"
    fi

    # CPU
    if [ -f /proc/cpuinfo ]; then
        local cpu_model
        cpu_model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/.*: //')
        local cpu_count
        cpu_count=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo '?')
        echo "CPU      : ${cpu_model:-Unknown} (${cpu_count} core(s))"
    elif command -v sysctl >/dev/null 2>&1; then
        echo "CPU      : $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'N/A')"
    else
        echo "CPU      : N/A"
    fi

    # Memory
    if [ -f /proc/meminfo ]; then
        local mem_total mem_free
        mem_total=$(awk '/MemTotal/  {printf "%.0f MB", $2/1024}' /proc/meminfo 2>/dev/null)
        mem_free=$(awk  '/MemAvailable/ {printf "%.0f MB", $2/1024}' /proc/meminfo 2>/dev/null)
        echo "Memory   : Total=${mem_total:-N/A}, Available=${mem_free:-N/A}"
    elif command -v free >/dev/null 2>&1; then
        echo "Memory   : $(free -h 2>/dev/null | awk '/Mem:/{print "Total="$2", Available="$7}' || echo 'N/A')"
    else
        echo "Memory   : N/A"
    fi

    echo "=============================="
}

cmd_check_host() {
    local host="${1:-}"
    if [ -z "$host" ]; then
        die 2 "check-host requires a <host> argument"
    fi

    echo "Checking host: $host"

    # Try to resolve the hostname
    local resolved=""
    if command -v getent >/dev/null 2>&1; then
        resolved=$(getent hosts "$host" 2>/dev/null | awk '{print $1; exit}')
    elif command -v nslookup >/dev/null 2>&1; then
        resolved=$(nslookup "$host" 2>/dev/null | awk '/^Address: /{print $2; exit}')
    elif command -v dig >/dev/null 2>&1; then
        resolved=$(dig +short "$host" 2>/dev/null | tail -n1)
    fi

    if [ -n "$resolved" ]; then
        echo "Resolved : $host -> $resolved"
    else
        echo "Resolved : $host (resolution info unavailable)"
    fi

    # Ping the host
    if command -v ping >/dev/null 2>&1; then
        echo "Pinging  : $host ..."
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1 || ping -c 1 -w 3 "$host" >/dev/null 2>&1; then
            echo "Result   : Host is reachable"
            return 0
        else
            echo "Result   : Host is unreachable" >&2
            return 1
        fi
    else
        echo "Result   : ping not available — skipping ICMP check"
        return 0
    fi
}

cmd_check_port() {
    local host="${1:-}"
    local port="${2:-}"

    # Validate arguments
    if [ -z "$host" ]; then
        die 2 "check-port requires <host> and <port> arguments"
    fi
    if [ -z "$port" ]; then
        die 2 "check-port requires a <port> argument"
    fi

    # Validate port is numeric (integer only, no leading +/-)
    case "$port" in
        ''|*[!0-9]*)
            die 2 "Port must be a numeric value between 1 and 65535 (got: '$port')"
            ;;
    esac

    # Validate port range: must be 1–65535
    # Use arithmetic carefully to stay POSIX-compatible
    if [ "$port" -le 0 ] 2>/dev/null; then
        die 2 "Port must be between 1 and 65535 (got: $port)"
    fi
    if [ "$port" -gt 65535 ] 2>/dev/null; then
        die 2 "Port must be between 1 and 65535 (got: $port)"
    fi

    echo "Checking TCP port: $host:$port ..."

    # Attempt connection using nc (netcat) first
    if command -v nc >/dev/null 2>&1; then
        if nc -z -w 3 "$host" "$port" >/dev/null 2>&1; then
            echo "Result   : Port $port on $host is OPEN"
            return 0
        else
            echo "Result   : Port $port on $host is CLOSED or unreachable" >&2
            return 1
        fi
    fi

    # Fallback: /dev/tcp (bash built-in)
    if (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1; then
        echo "Result   : Port $port on $host is OPEN"
        return 0
    else
        echo "Result   : Port $port on $host is CLOSED or unreachable" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Entry point — dispatch
# ---------------------------------------------------------------------------
main() {
    local command="${1:-}"

    if [ -z "$command" ]; then
        echo "ERROR: No command provided. Use 'help' for usage." >&2
        exit 2
    fi

    shift   # remaining args forwarded to sub-commands

    case "$command" in
        help|-h|--help)
            usage
            exit 0
            ;;
        system-info)
            cmd_system_info
            exit 0
            ;;
        check-host)
            cmd_check_host "$@"
            exit $?
            ;;
        check-port)
            cmd_check_port "$@"
            exit $?
            ;;
        *)
            echo "ERROR: Unknown command '$command'. Use 'help' for usage." >&2
            exit 2
            ;;
    esac
}

main "$@"
