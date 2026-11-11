#!/usr/bin/env bash

set -euo pipefail

# --------------------------------------------------
# Configuration
# --------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

LOG_FILE="${PROJECT_ROOT}/health_log.txt"
MAX_LOG_BYTES=1048576

DISK_WARNING=80
CPU_WARNING=90
MEM_WARNING=85

DISK_CRITICAL_ARG=""
CPU_CRITICAL_ARG=""
MEM_CRITICAL_ARG=""

JSON_MODE=false

# --------------------------------------------------
# Help and argument handling
# --------------------------------------------------

usage() {
    cat <<'HELP'
System Health Monitoring Script

Usage:
  ./scripts/system_health.sh [OPTIONS]

Options:
  --disk VALUE             Disk usage warning threshold (default: 80%)
  --cpu VALUE              CPU usage warning threshold (default: 90%)
  --mem VALUE              Memory usage warning threshold (default: 85%)

  --disk-critical VALUE    Disk critical threshold
  --cpu-critical VALUE     CPU critical threshold
  --mem-critical VALUE     Memory critical threshold

  --json                   Output results in JSON format
  --help, -h               Display this help

Default critical thresholds:
  Disk:   warning + 10 percentage points
  CPU:    warning + 5 percentage points
  Memory: warning + 10 percentage points

Critical thresholds are capped at 100%.

Exit codes:
  0 = Healthy
  1 = Warning
  2 = Critical or invalid configuration

The script checks:
  - CPU usage
  - Memory usage
  - All mounted filesystems
  - System load averages
  - Top five memory-consuming processes

Results are appended to health_log.txt in the project root.
The log is rotated at approximately 1 MB, retaining three backups.
HELP
}

error() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 2
}

validate_threshold() {
    local name="$1"
    local value="$2"

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        error "$name must be an integer between 1 and 100."
    fi

    if (( value < 1 || value > 100 )); then
        error "$name must be between 1 and 100."
    fi
}

while (($# > 0)); do
    case "$1" in
        --disk)
            (($# >= 2)) || error "Missing value for --disk."
            DISK_WARNING="$2"
            shift 2
            ;;
        --cpu)
            (($# >= 2)) || error "Missing value for --cpu."
            CPU_WARNING="$2"
            shift 2
            ;;
        --mem)
            (($# >= 2)) || error "Missing value for --mem."
            MEM_WARNING="$2"
            shift 2
            ;;
        --disk-critical)
            (($# >= 2)) || error "Missing value for --disk-critical."
            DISK_CRITICAL_ARG="$2"
            shift 2
            ;;
        --cpu-critical)
            (($# >= 2)) || error "Missing value for --cpu-critical."
            CPU_CRITICAL_ARG="$2"
            shift 2
            ;;
        --mem-critical)
            (($# >= 2)) || error "Missing value for --mem-critical."
            MEM_CRITICAL_ARG="$2"
            shift 2
            ;;
        --json)
            JSON_MODE=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

validate_threshold "Disk warning threshold" "$DISK_WARNING"
validate_threshold "CPU warning threshold" "$CPU_WARNING"
validate_threshold "Memory warning threshold" "$MEM_WARNING"

# Calculate default critical thresholds unless overridden.

DISK_CRITICAL="${DISK_CRITICAL_ARG:-$((DISK_WARNING + 10))}"
CPU_CRITICAL="${CPU_CRITICAL_ARG:-$((CPU_WARNING + 5))}"
MEM_CRITICAL="${MEM_CRITICAL_ARG:-$((MEM_WARNING + 10))}"

if (( DISK_CRITICAL > 100 )); then DISK_CRITICAL=100; fi
if (( CPU_CRITICAL > 100 )); then CPU_CRITICAL=100; fi
if (( MEM_CRITICAL > 100 )); then MEM_CRITICAL=100; fi

validate_threshold "Disk critical threshold" "$DISK_CRITICAL"
validate_threshold "CPU critical threshold" "$CPU_CRITICAL"
validate_threshold "Memory critical threshold" "$MEM_CRITICAL"

if (( DISK_CRITICAL < DISK_WARNING )); then
    error "Disk critical threshold cannot be below its warning threshold."
fi

if (( CPU_CRITICAL < CPU_WARNING )); then
    error "CPU critical threshold cannot be below its warning threshold."
fi

if (( MEM_CRITICAL < MEM_WARNING )); then
    error "Memory critical threshold cannot be below its warning threshold."
fi

# --------------------------------------------------
# Helper functions
# --------------------------------------------------

get_status() {
    local value="$1"
    local warning="$2"
    local critical="$3"

    awk -v value="$value" \
        -v warning="$warning" \
        -v critical="$critical" \
        'BEGIN {
            if (value >= critical) {
                print "CRITICAL"
            } else if (value >= warning) {
                print "WARNING"
            } else {
                print "HEALTHY"
            }
        }'
}

update_overall_status() {
    case "$1" in
        CRITICAL)
            OVERALL_STATUS="CRITICAL"
            ;;
        WARNING)
            if [[ "$OVERALL_STATUS" != "CRITICAL" ]]; then
                OVERALL_STATUS="WARNING"
            fi
            ;;
    esac
}

# --------------------------------------------------
# CPU monitoring
# --------------------------------------------------

read_cpu_counters() {
    local -a fields

    read -r -a fields < /proc/stat

    local user="${fields[1]:-0}"
    local nice="${fields[2]:-0}"
    local system="${fields[3]:-0}"
    local idle="${fields[4]:-0}"
    local iowait="${fields[5]:-0}"
    local irq="${fields[6]:-0}"
    local softirq="${fields[7]:-0}"
    local steal="${fields[8]:-0}"

    local total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    local idle_total=$((idle + iowait))

    printf '%s %s\n' "$total" "$idle_total"
}

read -r cpu_total_1 cpu_idle_1 < <(read_cpu_counters)

sleep 1

read -r cpu_total_2 cpu_idle_2 < <(read_cpu_counters)

cpu_total_delta=$((cpu_total_2 - cpu_total_1))
cpu_idle_delta=$((cpu_idle_2 - cpu_idle_1))

if (( cpu_total_delta > 0 )); then
    CPU_USAGE="$(awk \
        -v total="$cpu_total_delta" \
        -v idle="$cpu_idle_delta" \
        'BEGIN {
            printf "%.2f", ((total - idle) / total) * 100
        }')"
else
    CPU_USAGE="0.00"
fi

CPU_STATUS="$(get_status "$CPU_USAGE" "$CPU_WARNING" "$CPU_CRITICAL")"

# --------------------------------------------------
# Memory monitoring
# --------------------------------------------------

read -r MEM_TOTAL_KB MEM_AVAILABLE_KB < <(
    awk '
        /^MemTotal:/ {
            total = $2
        }
        /^MemAvailable:/ {
            available = $2
        }
        /^MemFree:/ {
            free_mem = $2
        }
        END {
            if (available == 0) {
                available = free_mem
            }

            if (total <= 0) {
                exit 1
            }

            printf "%d %d\n", total, available
        }
    ' /proc/meminfo
)

if (( MEM_AVAILABLE_KB > MEM_TOTAL_KB )); then
    MEM_AVAILABLE_KB="$MEM_TOTAL_KB"
fi

MEM_USED_KB=$((MEM_TOTAL_KB - MEM_AVAILABLE_KB))

MEMORY_USAGE="$(awk \
    -v used="$MEM_USED_KB" \
    -v total="$MEM_TOTAL_KB" \
    'BEGIN {
        if (total > 0) {
            printf "%.2f", (used / total) * 100
        } else {
            print "0.00"
        }
    }')"

MEM_USED_MB=$((MEM_USED_KB / 1024))
MEM_TOTAL_MB=$((MEM_TOTAL_KB / 1024))

MEMORY_STATUS="$(get_status "$MEMORY_USAGE" "$MEM_WARNING" "$MEM_CRITICAL")"

# --------------------------------------------------
# Disk monitoring
# --------------------------------------------------

declare -a DISK_FILESYSTEMS=()
declare -a DISK_MOUNTS=()
declare -a DISK_USAGE=()
declare -a DISK_STATUSES=()

MAX_DISK_USAGE=0

while IFS=$'\t' read -r filesystem usage mountpoint; do
    [[ -z "$filesystem" ]] && continue

    usage="${usage%\%}"

    [[ "$usage" =~ ^[0-9]+$ ]] || continue

    DISK_FILESYSTEMS+=("$filesystem")
    DISK_MOUNTS+=("$mountpoint")
    DISK_USAGE+=("$usage")

    if (( usage > MAX_DISK_USAGE )); then
        MAX_DISK_USAGE="$usage"
    fi
done < <(
    df -P -k | awk 'NR > 1 {
        print $1 "\t" $5 "\t" $6
    }'
)

if ((${#DISK_USAGE[@]} == 0)); then
    DISK_STATUS="CRITICAL"
else
    DISK_STATUS="$(get_status "$MAX_DISK_USAGE" "$DISK_WARNING" "$DISK_CRITICAL")"
fi

for index in "${!DISK_USAGE[@]}"; do
    DISK_STATUSES[index]="$(get_status \
        "${DISK_USAGE[$index]}" \
        "$DISK_WARNING" \
        "$DISK_CRITICAL")"
done

# --------------------------------------------------
# System load averages
# --------------------------------------------------

read -r LOAD_1M LOAD_5M LOAD_15M _ < /proc/loadavg

# --------------------------------------------------
# Top five memory-consuming processes
# --------------------------------------------------

declare -a PROCESS_ROWS=()
declare -a PROCESS_PIDS=()
declare -a PROCESS_COMMANDS=()
declare -a PROCESS_MEMORY=()
declare -a PROCESS_CPU=()

mapfile -t PROCESS_ROWS < <(
    ps -eo pid=,comm=,pmem=,pcpu= --sort=-pmem | awk 'NR <= 5'
)

for process_row in "${PROCESS_ROWS[@]}"; do
    read -r process_pid process_command process_mem process_cpu \
        <<< "$process_row"

    PROCESS_PIDS+=("$process_pid")
    PROCESS_COMMANDS+=("$process_command")
    PROCESS_MEMORY+=("$process_mem")
    PROCESS_CPU+=("$process_cpu")
done

# --------------------------------------------------
# Overall health status
# --------------------------------------------------

OVERALL_STATUS="HEALTHY"

update_overall_status "$CPU_STATUS"
update_overall_status "$MEMORY_STATUS"
update_overall_status "$DISK_STATUS"

case "$OVERALL_STATUS" in
    HEALTHY)
        EXIT_CODE=0
        ;;
    WARNING)
        EXIT_CODE=1
        ;;
    CRITICAL)
        EXIT_CODE=2
        ;;
esac

TIMESTAMP="$(date '+%Y-%m-%dT%H:%M:%S%:z')"

# --------------------------------------------------
# JSON escaping
# --------------------------------------------------

json_escape() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"

    printf '%s' "$value"
}

# --------------------------------------------------
# JSON report
# --------------------------------------------------

build_json_report() {
    printf '{'

    printf '"timestamp":"%s",' "$(json_escape "$TIMESTAMP")"
    printf '"status":"%s",' "$OVERALL_STATUS"
    printf '"exit_code":%s,' "$EXIT_CODE"

    printf '"thresholds":{'
    printf '"disk_warning_pct":%s,' "$DISK_WARNING"
    printf '"disk_critical_pct":%s,' "$DISK_CRITICAL"
    printf '"cpu_warning_pct":%s,' "$CPU_WARNING"
    printf '"cpu_critical_pct":%s,' "$CPU_CRITICAL"
    printf '"memory_warning_pct":%s,' "$MEM_WARNING"
    printf '"memory_critical_pct":%s' "$MEM_CRITICAL"
    printf '},'

    printf '"cpu":{'
    printf '"usage_pct":%s,' "$CPU_USAGE"
    printf '"status":"%s"' "$CPU_STATUS"
    printf '},'

    printf '"memory":{'
    printf '"used_pct":%s,' "$MEMORY_USAGE"
    printf '"used_mb":%s,' "$MEM_USED_MB"
    printf '"total_mb":%s,' "$MEM_TOTAL_MB"
    printf '"status":"%s"' "$MEMORY_STATUS"
    printf '},'

    printf '"load_average":{'
    printf '"1m":%s,' "$LOAD_1M"
    printf '"5m":%s,' "$LOAD_5M"
    printf '"15m":%s' "$LOAD_15M"
    printf '},'

    printf '"disk":{'
    printf '"max_used_pct":%s,' "$MAX_DISK_USAGE"
    printf '"status":"%s",' "$DISK_STATUS"
    printf '"filesystems":['

    for index in "${!DISK_FILESYSTEMS[@]}"; do
        if (( index > 0 )); then
            printf ','
        fi

        printf '{'
        printf '"filesystem":"%s",' "$(json_escape "${DISK_FILESYSTEMS[$index]}")"
        printf '"mountpoint":"%s",' "$(json_escape "${DISK_MOUNTS[$index]}")"
        printf '"used_pct":%s,' "${DISK_USAGE[$index]}"
        printf '"status":"%s"' "${DISK_STATUSES[$index]}"
        printf '}'
    done

    printf ']},'

    printf '"top_memory_processes":['

    for index in "${!PROCESS_PIDS[@]}"; do
        if (( index > 0 )); then
            printf ','
        fi

        printf '{'
        printf '"pid":%s,' "${PROCESS_PIDS[$index]}"
        printf '"command":"%s",' "$(json_escape "${PROCESS_COMMANDS[$index]}")"
        printf '"memory_pct":%s,' "${PROCESS_MEMORY[$index]}"
        printf '"cpu_pct":%s' "${PROCESS_CPU[$index]}"
        printf '}'
    done

    printf ']}'
}

# --------------------------------------------------
# Human-readable report
# --------------------------------------------------

build_text_report() {
    printf '%s\n' "=================================================="
    printf 'SYSTEM HEALTH REPORT\n'
    printf '%s\n' "=================================================="

    printf 'Timestamp: %s\n' "$TIMESTAMP"
    printf 'Overall status: %s\n' "$OVERALL_STATUS"
    printf 'Exit code: %s\n\n' "$EXIT_CODE"

    printf '%s\n' "--- CPU ---"
    printf 'Usage: %s%%\n' "$CPU_USAGE"
    printf 'Status: %s\n\n' "$CPU_STATUS"

    printf '%s\n' "--- MEMORY ---"
    printf 'Usage: %s%%\n' "$MEMORY_USAGE"
    printf 'Used: %s MB / %s MB\n' "$MEM_USED_MB" "$MEM_TOTAL_MB"
    printf 'Status: %s\n\n' "$MEMORY_STATUS"

    printf '%s\n' "--- DISK ---"
    printf 'Maximum filesystem usage: %s%%\n' "$MAX_DISK_USAGE"
    printf 'Status: %s\n' "$DISK_STATUS"

    for index in "${!DISK_FILESYSTEMS[@]}"; do
        printf '  %s mounted on %s: %s%% (%s)\n' \
            "${DISK_FILESYSTEMS[$index]}" \
            "${DISK_MOUNTS[$index]}" \
            "${DISK_USAGE[$index]}" \
            "${DISK_STATUSES[$index]}"
    done

    printf '\n%s\n' "--- LOAD AVERAGE ---"
    printf '1 minute:  %s\n' "$LOAD_1M"
    printf '5 minutes: %s\n' "$LOAD_5M"
    printf '15 minutes: %s\n' "$LOAD_15M"

    printf '\n%s\n' "--- TOP 5 MEMORY-CONSUMING PROCESSES ---"
    printf '%-10s %-25s %-12s %-12s\n' "PID" "COMMAND" "MEMORY%" "CPU%"

    for index in "${!PROCESS_PIDS[@]}"; do
        printf '%-10s %-25s %-12s %-12s\n' \
            "${PROCESS_PIDS[$index]}" \
            "${PROCESS_COMMANDS[$index]}" \
            "${PROCESS_MEMORY[$index]}" \
            "${PROCESS_CPU[$index]}"
    done

    printf '\n%s\n' "=================================================="
}

# --------------------------------------------------
# Log rotation
# --------------------------------------------------

rotate_log() {
    if [[ ! -f "$LOG_FILE" ]]; then
        return
    fi

    local current_size
    current_size="$(wc -c < "$LOG_FILE")"

    if (( current_size >= MAX_LOG_BYTES )); then
        rm -f "${LOG_FILE}.3"

        if [[ -f "${LOG_FILE}.2" ]]; then
            mv -f "${LOG_FILE}.2" "${LOG_FILE}.3"
        fi

        if [[ -f "${LOG_FILE}.1" ]]; then
            mv -f "${LOG_FILE}.1" "${LOG_FILE}.2"
        fi

        mv -f "$LOG_FILE" "${LOG_FILE}.1"
    fi
}

# --------------------------------------------------
# Generate and save report
# --------------------------------------------------

rotate_log

if [[ "$JSON_MODE" == true ]]; then
    REPORT="$(build_json_report)"
else
    REPORT="$(build_text_report)"
fi

if [[ "$JSON_MODE" == true ]]; then
    printf '%s\n' "$REPORT" | tee -a "$LOG_FILE"
else
    printf '%s\n' "$REPORT" | tee -a "$LOG_FILE"
    printf '\nReport saved to: %s\n' "$LOG_FILE"
fi

exit "$EXIT_CODE"
