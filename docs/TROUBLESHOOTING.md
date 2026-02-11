# Troubleshooting Guide

## Fan Oscillation / Hammering Noise

**Symptom:** Fans constantly change speed, creating an annoying oscillating/hammering noise.

**Root Cause:** The BMC is fighting the fan control script for control, causing rapid speed changes.

### Solution 1: BMC Safety Mode Reset

The BMC may have entered safety mode after detecting fan critical alarms:

```bash
# 1. Clear system event log
sudo ipmitool sel clear

# 2. Cold reset the BMC
sudo ipmitool mc reset cold

# 3. Wait 2 minutes for BMC to recover
sleep 120

# 4. Restart fan control
sudo systemctl restart fan-control.service
```

### Solution 2: Adjust Polling Interval

If oscillation persists, the polling interval might be wrong for your BMC firmware:

```bash
sudo nano /usr/local/bin/fan-control.sh
```

Try different values:
- **0.3s** - More aggressive (older BMC firmware)
- **0.4s** - Recommended (tested on X11SSH-F)
- **0.5s** - More conservative (newer BMC firmware)

Then restart:
```bash
sudo systemctl restart fan-control.service
```

### Solution 3: Check for IPMI Collisions

If you see errors like "Received a response with unexpected ID":

```bash
sudo journalctl -u fan-control.service -n 100 | grep "unexpected ID"
```

**Fix:** Increase polling interval to 0.5s or higher.

---

## Fans Running at Full Speed

**Symptom:** All fans running at maximum RPM constantly.

### Diagnostic Steps

1. **Check if service is running:**
```bash
sudo systemctl status fan-control.service
```

2. **Check for errors in logs:**
```bash
sudo journalctl -u fan-control.service -n 50
```

3. **Verify manual mode is enabled:**
```bash
sudo ipmitool raw 0x30 0x45 0x00
# Should return: 01 (manual mode)
# If returns: 00 (automatic mode) - BMC has reclaimed control
```

### Solutions

**If service is not running:**
```bash
sudo systemctl start fan-control.service
```

**If BMC is in automatic mode:**
The script might not be hammering fast enough. See "Fan Oscillation" above.

**If too many IPMI failures:**
Check logs for "Too many IPMI failures" message. The script auto-maxes fans for safety.
- Reduce polling interval
- Check IPMI connectivity
- Verify ipmitool works: `sudo ipmitool sensor | grep FAN`

---

## Temperatures Rising / Fans Too Quiet

**Symptom:** CPU or peripheral temperatures are higher than comfortable.

### Solution: Adjust Fan Curves

Edit the configuration in `/usr/local/bin/fan-control.sh`:

```bash
# Make fans more aggressive:
CPU_TEMP_LOW=45       # Start ramping earlier (was 50)
CPU_DUTY_MIN=40       # Higher minimum speed (was 30)
CPU_DUTY_MAX=90       # Higher maximum speed (was 70)

# Or reduce temperature thresholds:
CPU_TEMP_HIGH=70      # Max speed at lower temp (was 75)
```

**Then restart:**
```bash
sudo systemctl restart fan-control.service
```

**Monitor temperatures:**
```bash
watch -n 2 'ipmitool sensor | grep -E "Temp|FAN"'
```

---

## IPMI Command Errors

**Symptom:** Errors in logs like:
- "Unable to send command: Device or resource is busy"
- "Get SDR command failed"
- "Received a response with unexpected ID"

### Cause
Polling interval is too fast, causing IPMI interface saturation.

### Solution
```bash
sudo nano /usr/local/bin/fan-control.sh
# Increase POLL_INTERVAL from 0.4 to 0.5 or 0.6
```

---

## BMC Firmware Update Broke Control

**Symptom:** Fan control worked before, stopped after BMC firmware update.

### Diagnostic
Check if manual mode command has changed:
```bash
# Try standard command
sudo ipmitool raw 0x30 0x45 0x01

# Check mode
sudo ipmitool raw 0x30 0x45 0x00
```

### Solution
BMC firmware updates can change fan control behavior. You may need to:
1. Adjust polling interval
2. Clear SEL and reset BMC (see "Fan Oscillation" section)
3. Check Supermicro documentation for new commands

---

## Service Won't Start

**Symptom:** `systemctl start fan-control.service` fails.

### Check Dependencies
```bash
# fan-control requires fan-init
sudo systemctl status fan-init.service

# Make sure ipmitool is installed
which ipmitool
```

### Check Permissions
```bash
# Script must be executable
ls -l /usr/local/bin/fan-control.sh
# Should show: -rwxr-xr-x

# Fix if needed:
sudo chmod +x /usr/local/bin/fan-control.sh
```

### Check Logs
```bash
sudo journalctl -u fan-control.service -n 50 -o cat
```

---

## Uninstall / Return to Automatic Mode

To remove fan control and return to BMC automatic mode:

```bash
# Stop and disable services
sudo systemctl stop fan-control.service
sudo systemctl stop fan-healthcheck.timer
sudo systemctl disable fan-control.service
sudo systemctl disable fan-init.service
sudo systemctl disable fan-healthcheck.timer

# Restore automatic mode
sudo ipmitool raw 0x30 0x45 0x02

# Remove files
sudo rm /usr/local/bin/fan-control.sh
sudo rm /usr/local/bin/fan-init.sh
sudo rm /usr/local/bin/fan-healthcheck.sh
sudo rm /etc/systemd/system/fan-*.service
sudo rm /etc/systemd/system/fan-healthcheck.timer

# Reload systemd
sudo systemctl daemon-reload
```

---

## Getting Help

If you're still having issues:

1. **Collect diagnostic info:**
```bash
# System info
uname -a
ipmitool mc info

# Service status
systemctl status fan-control.service

# Recent logs
journalctl -u fan-control.service -n 100

# Current fan speeds and temps
ipmitool sensor | grep -E "Temp|FAN"

# BMC mode
ipmitool raw 0x30 0x45 0x00
```

2. **Open an issue on GitHub** with the above information

3. **Check existing issues** - someone may have had the same problem
