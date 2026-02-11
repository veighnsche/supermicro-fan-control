# Supermicro X11SSH-F Fan Control

**Intelligent fan curve control for Supermicro X11SSH-F motherboards**

Stop the annoying fan speed oscillations and take control of your server's cooling with temperature-based fan curves that actually work.

## 🎯 Features

- **Custom fan curves** - Set your own temperature thresholds and fan speeds
- **Prevents BMC oscillation** - Optimized polling interval to maintain control without IPMI errors
- **Safe defaults** - 30% minimum duty cycle prevents BMC safety lockouts
- **Auto-recovery** - Service automatically restarts on failure
- **Health monitoring** - Optional healthcheck timer
- **Quiet operation** - Reduces fan noise from ~2800 RPM to ~500-700 RPM at idle

## 🔧 Hardware Support

**Tested on:**
- Supermicro X11SSH-F motherboard
- IPMI/BMC with standard Supermicro fan control interface

**Fan Zones:**
- **Zone 0 (CPU)**: FAN1-FAN4 (CPU fans)
- **Zone 1 (Peripheral)**: FANA (chassis/HBA fans)

## 📋 Prerequisites

- `ipmitool` installed
- Root access or sudo privileges
- Systemd-based Linux distribution

## 🚀 Installation

**One-line install:**
```bash
curl -sSL https://raw.githubusercontent.com/YOUR-USERNAME/supermicro-fan-control/main/install.sh | sudo bash
```

**Manual install:**
```bash
git clone https://github.com/YOUR-USERNAME/supermicro-fan-control.git
cd supermicro-fan-control
sudo ./install.sh
```

The installer will:
1. Install scripts to `/usr/local/bin/`
2. Install systemd services
3. Enable and start the fan control service
4. Set fans to max speed on boot for safety

## ⚙️ Configuration

Edit `/usr/local/bin/fan-control.sh` to customize:

```bash
# Temperature curve for CPU zone (°C)
cpu_duty=$(calc_duty "$cpu_temp" 50 75 30 70)
#                                 │   │  │  └─ Max duty at high temp
#                                 │   │  └──── Min duty at low temp
#                                 │   └─────── High temp threshold (75°C)
#                                 └─────────── Low temp threshold (50°C)

# Temperature curve for peripheral zone (°C)
periph_duty=$(calc_duty "$periph_temp" 45 65 30 60)
```

**Key settings:**
- `TEMP_INTERVAL=6` - Read temps every 6 cycles (~2.4 seconds)
- `sleep 0.4` - Polling interval (0.4s = sweet spot for X11SSH-F)
- Minimum duty: `30%` - Safe minimum to prevent BMC safety lockout

## 🩺 Troubleshooting

### Fan oscillation still occurs

The BMC may be in safety mode from previous fan critical alarms:

```bash
# Clear system event log
sudo ipmitool sel clear

# Cold reset BMC
sudo ipmitool mc reset cold

# Wait 2 minutes for BMC to recover, then restart service
sudo systemctl restart fan-control.service
```

### Fans run at full speed

Check service status:
```bash
sudo systemctl status fan-control.service
sudo journalctl -u fan-control.service -n 50
```

Verify manual mode is working:
```bash
sudo ipmitool raw 0x30 0x45 0x00  # Should return: 01 (manual mode)
```

### Too aggressive / IPMI errors

If you see "Received a response with unexpected ID" errors:
- Increase `sleep` interval in script (try 0.5 or 0.6)
- Hammering too fast causes IPMI command collisions

### Fans too quiet / temperatures rising

Adjust minimum duty cycle higher (e.g., 40% instead of 30%):
```bash
sudo nano /usr/local/bin/fan-control.sh
# Change: calc_duty "$cpu_temp" 50 75 40 70
sudo systemctl restart fan-control.service
```

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for more details.

## 📊 Monitoring

**Check current fan speeds:**
```bash
sudo ipmitool sensor | grep FAN
```

**Watch live log:**
```bash
tail -f /var/log/fan-control.log
```

**Service status:**
```bash
sudo systemctl status fan-control.service
```

## 🛡️ Safety Features

1. **Fan safety init** - Sets fans to max speed at boot before control starts
2. **Fail-safe** - On too many IPMI errors, fans go to 100%
3. **Auto-restart** - Service restarts automatically on failure
4. **Cleanup handler** - Restores automatic mode when service stops
5. **Minimum speed** - 30% prevents triggering BMC safety lockouts

## 🔬 How It Works

The Supermicro BMC aggressively reclaims fan control in automatic mode. This script:

1. **Polls every 0.4 seconds** to maintain manual fan control
2. **Reads temperatures every 2.4 seconds** (reduces IPMI overhead)
3. **Calculates duty cycle** based on temperature curves
4. **Applies duty to both fan zones** (CPU and peripheral)

The 0.4s interval is the sweet spot:
- **Too slow (>0.5s)**: BMC reclaims control → oscillation
- **Too fast (<0.3s)**: IPMI command collisions → errors

## 🐛 Known Issues

- **BMC firmware updates** may change fan control behavior
- **IPMI collisions** can occur on some systems (adjust sleep interval)
- **BMC safety mode** can trigger from fan speeds <30% (cleared by BMC reset)

## 📝 License

MIT License - See [LICENSE](LICENSE) file

## 🙏 Contributing

Contributions welcome! Please open an issue or PR.

**Tested configurations appreciated:**
- Other Supermicro X11 boards
- Different BMC firmware versions
- Alternative polling intervals

## ⚠️ Disclaimer

**Use at your own risk.** Monitor temperatures when first deploying. This script disables the BMC's automatic fan control. Ensure your temperature curves are appropriate for your workload.

## 📚 References

- [Supermicro IPMI Fan Control Commands](https://www.supermicro.com/support/faqs/)
- [ipmitool Documentation](https://github.com/ipmitool/ipmitool)

---

**Made with ❤️ for quiet homelabs**
