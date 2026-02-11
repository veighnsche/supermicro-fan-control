#!/bin/bash
###############################################################################
# Supermicro X11SSH-F Fan Control - Installation Script
# https://github.com/YOUR-USERNAME/supermicro-fan-control
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo_error "This script must be run as root (use sudo)"
   exit 1
fi

echo_info "Installing Supermicro X11SSH-F Fan Control..."
echo

# Check prerequisites
echo_info "Checking prerequisites..."
if ! command -v ipmitool &> /dev/null; then
    echo_error "ipmitool not found!"
    echo "Install it with: apt-get install ipmitool  (Debian/Ubuntu)"
    echo "                 yum install ipmitool      (RHEL/CentOS)"
    exit 1
fi

if ! command -v systemctl &> /dev/null; then
    echo_error "systemd not found! This script requires systemd."
    exit 1
fi

# Detect installation directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo_info "Installing from: $SCRIPT_DIR"
echo

# Install scripts
echo_info "Installing scripts to /usr/local/bin/..."
install -m 755 "$SCRIPT_DIR/bin/fan-control.sh" /usr/local/bin/fan-control.sh
install -m 755 "$SCRIPT_DIR/bin/fan-init.sh" /usr/local/bin/fan-init.sh
install -m 755 "$SCRIPT_DIR/bin/fan-healthcheck.sh" /usr/local/bin/fan-healthcheck.sh

# Install systemd service files
echo_info "Installing systemd service files..."
install -m 644 "$SCRIPT_DIR/systemd/fan-control.service" /etc/systemd/system/
install -m 644 "$SCRIPT_DIR/systemd/fan-init.service" /etc/systemd/system/
install -m 644 "$SCRIPT_DIR/systemd/fan-healthcheck.service" /etc/systemd/system/
install -m 644 "$SCRIPT_DIR/systemd/fan-healthcheck.timer" /etc/systemd/system/

# Reload systemd
echo_info "Reloading systemd daemon..."
systemctl daemon-reload

# Enable services
echo_info "Enabling services..."
systemctl enable fan-init.service
systemctl enable fan-control.service
systemctl enable fan-healthcheck.timer

# Ask user if they want to start now
echo
echo_warn "IMPORTANT: This will take control of your server's fans."
echo_warn "Make sure you've reviewed the temperature curves in /usr/local/bin/fan-control.sh"
echo
read -p "Start fan control now? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo_info "Starting services..."
    systemctl start fan-init.service
    sleep 2
    systemctl start fan-control.service
    sleep 2
    systemctl start fan-healthcheck.timer

    echo
    echo_info "Checking service status..."
    systemctl status fan-control.service --no-pager -l

    echo
    echo_info "Current fan speeds:"
    ipmitool sensor | grep FAN || true

    echo
    echo_info "Watch logs with: journalctl -u fan-control.service -f"
    echo_info "Or: tail -f /var/log/fan-control.log"
else
    echo_warn "Services enabled but not started."
    echo_info "Start manually with:"
    echo "  systemctl start fan-init.service"
    echo "  systemctl start fan-control.service"
    echo "  systemctl start fan-healthcheck.timer"
fi

echo
echo_info "Installation complete!"
echo
echo "Configuration file: /usr/local/bin/fan-control.sh"
echo "Log file: /var/log/fan-control.log"
echo "Systemd services: fan-init, fan-control, fan-healthcheck.timer"
echo
echo "Next steps:"
echo "  1. Review/customize temperature curves in /usr/local/bin/fan-control.sh"
echo "  2. Monitor temperatures and fan speeds for a few hours"
echo "  3. Adjust curves if needed and restart: systemctl restart fan-control.service"
echo
