#!/bin/bash
###############################################################################
# Supermicro X11SSH-F Fan Control Script
# https://github.com/YOUR-USERNAME/supermicro-fan-control
#
# Implements temperature-based fan curves with manual BMC fan control
# to prevent oscillation and reduce noise on Supermicro X11SSH-F boards.
#
# Zone 0 (CPU): FAN1-FAN4 (CPU fans)
# Zone 1 (Peripheral): FANA (chassis/HBA fans)
###############################################################################

set -o pipefail

###############################################################################
# CONFIGURATION
###############################################################################

# Temperature sensor names (as reported by ipmitool)
CPU_SENSOR="CPU Temp"
PERIPH_SENSOR="Peripheral Temp"

# How often to read temperatures (in cycles, not seconds)
# With 0.4s sleep, 6 cycles = every 2.4 seconds
TEMP_INTERVAL=6

# Polling interval (seconds)
# 0.4s is the sweet spot for X11SSH-F:
#   - Fast enough to maintain manual mode
#   - Slow enough to avoid IPMI command collisions
POLL_INTERVAL=0.4

# IPMI command timeout (seconds)
IPMITOOL_TIMEOUT=5

# Log file location
LOG_FILE="/var/log/fan-control.log"

# Safety: Max consecutive IPMI failures before maxing fans
MAX_IPMI_FAILS=5

# CPU Fan Curve (Zone 0)
# Format: calc_duty TEMP LOW_TEMP HIGH_TEMP MIN_DUTY MAX_DUTY
#   - Below LOW_TEMP: runs at MIN_DUTY
#   - Above HIGH_TEMP: runs at MAX_DUTY
#   - Between: linear interpolation
CPU_TEMP_LOW=50      # Start ramping up at 50°C
CPU_TEMP_HIGH=75     # Max speed at 75°C
CPU_DUTY_MIN=30      # 30% minimum (prevents BMC safety lockout)
CPU_DUTY_MAX=70      # 70% maximum at high temp
CPU_TEMP_CRIT=80     # Emergency: 100% above this

# Peripheral Fan Curve (Zone 1)
PERIPH_TEMP_LOW=45
PERIPH_TEMP_HIGH=65
PERIPH_DUTY_MIN=30
PERIPH_DUTY_MAX=60
PERIPH_TEMP_CRIT=70

###############################################################################
# SCRIPT LOGIC (no need to modify below this line)
###############################################################################

# Initialize state
cpu_duty_hex="0x1e"      # Start at 30% (0x1e)
periph_duty_hex="0x1e"
cycle=0
ipmi_fail_count=0

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check prerequisites
check_prerequisites() {
    if ! command -v ipmitool &> /dev/null; then
        log_msg "ERROR: ipmitool not found. Please install: apt-get install ipmitool"
        exit 1
    fi
    if ! touch "$LOG_FILE" 2>/dev/null; then
        log_msg "WARNING: Cannot write to $LOG_FILE, using stdout only"
        LOG_FILE=""
    fi
}

# Calculate fan duty based on temperature curve
calc_duty() {
    local temp=$1 temp_low=$2 temp_high=$3 min_duty=$4 max_duty=$5

    if (( temp <= temp_low )); then
        echo "$min_duty"
    elif (( temp >= temp_high )); then
        echo "$max_duty"
    else
        # Linear interpolation
        echo $(( min_duty + (max_duty - min_duty) * (temp - temp_low) / (temp_high - temp_low) ))
    fi
}

# Read temperature with timeout and validation
read_temp() {
    local sensor_name="$1"
    local temp

    temp=$(timeout "$IPMITOOL_TIMEOUT" ipmitool sensor reading "$sensor_name" 2>/dev/null | awk -F'|' '{print int($2)}')

    # Validate: numeric and in reasonable range (-50 to 150°C)
    if [[ "$temp" =~ ^[0-9]+$ ]] && (( temp > -50 && temp < 150 )); then
        echo "$temp"
        return 0
    else
        return 1
    fi
}

# Send IPMI command with error checking
ipmi_cmd() {
    if ! timeout "$IPMITOOL_TIMEOUT" ipmitool "$@" > /dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Enable manual fan control mode
enable_manual_mode() {
    if ipmi_cmd raw 0x30 0x45 0x01; then
        ipmi_fail_count=0
        return 0
    else
        ((ipmi_fail_count++))
        return 1
    fi
}

# Set fan duty for specific zone
set_fan_duty() {
    local zone=$1 duty_hex=$2

    if ipmi_cmd raw 0x30 0x70 0x66 0x01 "$zone" "$duty_hex"; then
        ipmi_fail_count=0
        return 0
    else
        ((ipmi_fail_count++))
        return 1
    fi
}

# Cleanup: restore automatic mode on exit
cleanup() {
    log_msg "Caught exit signal, restoring automatic fan control..."
    timeout "$IPMITOOL_TIMEOUT" ipmitool raw 0x30 0x45 0x02 > /dev/null 2>&1
    log_msg "Fan control service stopped"
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

###############################################################################
# MAIN LOOP
###############################################################################

check_prerequisites
log_msg "Fan control service started (PID: $$)"
log_msg "Configuration: CPU=${CPU_TEMP_LOW}-${CPU_TEMP_HIGH}°C → ${CPU_DUTY_MIN}-${CPU_DUTY_MAX}%, Peripheral=${PERIPH_TEMP_LOW}-${PERIPH_TEMP_HIGH}°C → ${PERIPH_DUTY_MIN}-${PERIPH_DUTY_MAX}%"

# Initial mode enable
if ! enable_manual_mode; then
    log_msg "WARNING: Failed to enable manual mode on startup"
fi

while true; do
    # Safety: If too many IPMI failures, max out fans
    if (( ipmi_fail_count > MAX_IPMI_FAILS )); then
        log_msg "ERROR: Too many IPMI failures ($ipmi_fail_count). Setting fans to 100% for safety."
        cpu_duty_hex="0xff"
        periph_duty_hex="0xff"
        ipmi_fail_count=0
    fi

    # Re-read temperatures every TEMP_INTERVAL cycles
    if (( cycle % TEMP_INTERVAL == 0 )); then
        cpu_temp=$(read_temp "$CPU_SENSOR") || cpu_temp=""
        periph_temp=$(read_temp "$PERIPH_SENSOR") || periph_temp=""

        if [[ -z "$cpu_temp" || -z "$periph_temp" ]]; then
            log_msg "WARNING: Failed to read temperatures (CPU: '$cpu_temp', Periph: '$periph_temp')"
            # Keep previous duty settings, will retry next interval
        else
            # Calculate CPU fan duty
            if (( cpu_temp >= CPU_TEMP_CRIT )); then
                cpu_duty=100
            else
                cpu_duty=$(calc_duty "$cpu_temp" "$CPU_TEMP_LOW" "$CPU_TEMP_HIGH" "$CPU_DUTY_MIN" "$CPU_DUTY_MAX")
            fi

            # Calculate peripheral fan duty
            if (( periph_temp >= PERIPH_TEMP_CRIT )); then
                periph_duty=100
            else
                periph_duty=$(calc_duty "$periph_temp" "$PERIPH_TEMP_LOW" "$PERIPH_TEMP_HIGH" "$PERIPH_DUTY_MIN" "$PERIPH_DUTY_MAX")
            fi

            # Convert to hex
            cpu_duty_hex="0x$(printf '%02x' "$cpu_duty")"
            periph_duty_hex="0x$(printf '%02x' "$periph_duty")"

            log_msg "CPU: ${cpu_temp}°C → ${cpu_duty}%  |  Peripheral: ${periph_temp}°C → ${periph_duty}%"
        fi
    fi

    # Apply fan control settings
    # Re-enable manual mode every cycle (BMC tries to reclaim control)
    if ! enable_manual_mode; then
        log_msg "WARNING: Failed to set manual mode (cycle $cycle)"
    fi

    if ! set_fan_duty 0x00 "$cpu_duty_hex"; then
        log_msg "WARNING: Failed to set CPU fan duty (cycle $cycle)"
    fi

    if ! set_fan_duty 0x01 "$periph_duty_hex"; then
        log_msg "WARNING: Failed to set peripheral fan duty (cycle $cycle)"
    fi

    cycle=$((cycle + 1))
    sleep "$POLL_INTERVAL"
done
