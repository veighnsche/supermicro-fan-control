#!/bin/bash
###############################################################################
# Fan Control Health Check
# Verifies fan-control service is running and fans are responding
###############################################################################

LOG_FILE="/var/log/fan-control.log"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] HEALTHCHECK: $1"
}

# Check if service is active
if ! systemctl is-active --quiet fan-control.service; then
    log_msg "ERROR: fan-control.service is not active!"
    exit 1
fi

# Check if fans are reporting speeds
fan_count=$(ipmitool sensor | grep -c "^FAN.*RPM.*ok")

if (( fan_count == 0 )); then
    log_msg "ERROR: No fans are reporting OK status!"
    exit 1
fi

log_msg "OK: Service active, $fan_count fans responding"
exit 0
