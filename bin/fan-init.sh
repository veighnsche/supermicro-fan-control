#!/bin/bash
###############################################################################
# Fan Safety Initialization
# Runs early in boot to set fans to maximum before fan-control takes over
# This ensures safe operation if fan-control fails to start
###############################################################################

set -e

LOG="/var/log/fan-init.log"
exec > >(tee -a "$LOG")
exec 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fan safety init starting..."

# Try up to 10 times to enable manual mode (BMC might not be ready yet)
for attempt in {1..10}; do
    if /usr/bin/ipmitool raw 0x30 0x45 0x01 > /dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Manual fan mode enabled (attempt $attempt)"

        # Set both zones to maximum (0xFF = 100%)
        if /usr/bin/ipmitool raw 0x30 0x70 0x66 0x01 0x00 0xff > /dev/null 2>&1; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] CPU fans set to MAX"
        fi
        if /usr/bin/ipmitool raw 0x30 0x70 0x66 0x01 0x01 0xff > /dev/null 2>&1; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Peripheral fans set to MAX"
        fi

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fan safety init completed successfully"
        exit 0
    fi
    sleep 0.5
done

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to initialize fans after 10 attempts!"
exit 1
