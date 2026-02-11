#!/bin/bash
# Fan curve script for Supermicro X11SSH-F
# Zone 0 (CPU): FAN1-FAN4 (FAN1/FAN2 = 60mm, FAN4 = 120mm CPU)
# Zone 1 (Peripheral): FANA (120mm SAS HBA)
#
# BMC reclaims fan control periodically, re-send duty every cycle.
# Using 0.5s interval to avoid IPMI collisions and BMC safety lockouts.

set -o pipefail

TEMP_INTERVAL=6
LOG_FILE="/var/log/fan-control.log"
IPMITOOL_TIMEOUT=5
cpu_duty_hex="0x1e"
periph_duty_hex="0x1e"
cycle=0
ipmi_fail_count=0
max_ipmi_fails=5

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check prerequisites
check_prerequisites() {
    if ! command -v ipmitool &> /dev/null; then
        log_msg "ERROR: ipmitool not found"
        exit 1
    fi
    if ! touch "$LOG_FILE" 2>/dev/null; then
        log_msg "WARNING: Cannot write to $LOG_FILE, using stdout only"
        LOG_FILE=""
    fi
}

calc_duty() {
    local temp=$1 temp_low=$2 temp_high=$3 min_duty=$4 max_duty=$5
    if (( temp <= temp_low )); then
        echo "$min_duty"
    elif (( temp >= temp_high )); then
        echo "$max_duty"
    else
        echo $(( min_duty + (max_duty - min_duty) * (temp - temp_low) / (temp_high - temp_low) ))
    fi
}

# Safely read temperature with timeout and validation
read_temp() {
    local sensor_name="$1"
    local timeout_val=$IPMITOOL_TIMEOUT

    local temp
    temp=$(timeout $timeout_val ipmitool sensor reading "$sensor_name" 2>/dev/null | awk -F'|' '{print int($2)}')

    # Validate temperature is a number and in reasonable range (-50 to 150°C)
    if [[ "$temp" =~ ^[0-9]+$ ]] && (( temp > -50 && temp < 150 )); then
        echo "$temp"
        return 0
    else
        return 1
    fi
}

# Send ipmitool command with error checking
ipmi_cmd() {
    local timeout_val=$IPMITOOL_TIMEOUT
    if ! timeout $timeout_val ipmitool "$@" > /dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Enable manual fan control mode
enable_manual_mode() {
    if ipmi_cmd raw 0x30 0x45 0x01 0x01; then
        ipmi_fail_count=0
        return 0
    else
        ((ipmi_fail_count++))
        return 1
    fi
}

# Set fan duty for zone
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

cleanup() {
    log_msg "Restoring automatic fan control..."
    timeout $IPMITOOL_TIMEOUT ipmitool raw 0x30 0x45 0x02 > /dev/null 2>&1
    log_msg "Fan control service stopped"
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

check_prerequisites
log_msg "Fan control service started (PID: $$)"

# Initial mode enable
if ! enable_manual_mode; then
    log_msg "WARNING: Failed to enable manual mode on startup"
fi

while true; do
    # Check for too many IPMI failures - fail safe by boosting fans
    if (( ipmi_fail_count > max_ipmi_fails )); then
        log_msg "ERROR: Too many IPMI failures ($ipmi_fail_count). Maxing out fans for safety."
        cpu_duty_hex="0xff"
        periph_duty_hex="0xff"
        ipmi_fail_count=0
    fi

    # Re-read temps every TEMP_INTERVAL cycles
    if (( cycle % TEMP_INTERVAL == 0 )); then
        cpu_temp=$(read_temp "CPU Temp") || cpu_temp=""
        periph_temp=$(read_temp "Peripheral Temp") || periph_temp=""

        if [[ -z "$cpu_temp" || -z "$periph_temp" ]]; then
            log_msg "WARNING: Failed to read temperatures (CPU: '$cpu_temp', Periph: '$periph_temp')"
            # Keep previous duty settings, will retry next interval
        else
            if (( cpu_temp >= 80 )); then
                cpu_duty=100
            else
                cpu_duty=$(calc_duty "$cpu_temp" 50 75 30 70)
            fi

            if (( periph_temp >= 70 )); then
                periph_duty=100
            else
                periph_duty=$(calc_duty "$periph_temp" 45 65 30 60)
            fi

            cpu_duty_hex="0x$(printf '%02x' $cpu_duty)"
            periph_duty_hex="0x$(printf '%02x' $periph_duty)"

            log_msg "CPU: ${cpu_temp}°C → ${cpu_duty}%  |  Peripheral: ${periph_temp}°C → ${periph_duty}%"
        fi
    fi

    # Apply duty cycles (do NOT re-enable manual mode - causes oscillation!)
    # Full Speed mode (0x01 0x01) is enabled once at startup
    if ! set_fan_duty 0x00 "$cpu_duty_hex"; then
        log_msg "WARNING: Failed to set CPU fan duty (cycle $cycle)"
    fi
    if ! set_fan_duty 0x01 "$periph_duty_hex"; then
        log_msg "WARNING: Failed to set peripheral fan duty (cycle $cycle)"
    fi

    cycle=$((cycle + 1))
    sleep 0.4
done
