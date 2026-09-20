#!/bin/bash
# OCuLink GPU Hot-plug Safety Installation Script

set -e

# Resolve the directory this script lives in; all payload files are expected
# to sit next to it.
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"

echo "🔌 OCuLink GPU Hot-plug Safety Setup"
echo "===================================="
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root (use sudo)"
    exit 1
fi

BIN_FILES=(
    oculink-gpu-manager
    oculink-gpu-watcher
    oculink-reconnect-monitor
    oculink-removal-watcher
    oculink-kernel-config
    gpu-safe-remove
)
UDEV_FILES=(99-oculink-gpu-hotplug.rules)
SERVICE_FILES=(
    oculink-gpu-monitor.service
    oculink-kernel-safety.service
)

# Make sure everything we need is present before touching the system
missing=()
for f in "${BIN_FILES[@]}" "${UDEV_FILES[@]}" "${SERVICE_FILES[@]}"; do
    [ -f "$SCRIPT_DIR/$f" ] || missing+=("$f")
done
if [ ${#missing[@]} -ne 0 ]; then
    echo "❌ Missing files in $SCRIPT_DIR:"
    printf '   • %s\n' "${missing[@]}"
    exit 1
fi

echo "📁 Installing files from $SCRIPT_DIR..."

# Install scripts
for f in "${BIN_FILES[@]}"; do
    install -m 755 "$SCRIPT_DIR/$f" /usr/local/bin/
done

# Install udev rules
for f in "${UDEV_FILES[@]}"; do
    install -m 644 "$SCRIPT_DIR/$f" /etc/udev/rules.d/
done

# Install systemd services
for f in "${SERVICE_FILES[@]}"; do
    install -m 644 "$SCRIPT_DIR/$f" /etc/systemd/system/
done

echo "🔄 Reloading system configuration..."

# Reload udev rules
udevadm control --reload-rules
udevadm trigger

# Reload and enable systemd services
systemctl daemon-reload
systemctl enable oculink-gpu-monitor.service
systemctl enable oculink-kernel-safety.service
# restart (not start) so re-running the installer picks up updated binaries
systemctl restart oculink-gpu-monitor.service
systemctl restart oculink-kernel-safety.service

# Create log directory
mkdir -p /var/log
touch /var/log/oculink-gpu-manager.log
touch /var/log/oculink-gpu-watcher.log
touch /var/log/oculink-reconnect.log
touch /var/log/oculink-removal-watcher.log
chmod 644 /var/log/oculink-*.log

echo "✅ Installation complete!"
echo
echo "📋 Usage:"
echo "   • Automatic: GPU will be safely prepared when unplugged"
echo "   • Manual: Run 'gpu-safe-remove' before unplugging"
echo "   • Smart reconnection: Auto-detects when you plug it back in"
echo "   • Logs: Check /var/log/oculink-*.log for details"
echo "   • Monitor status: 'oculink-reconnect-monitor status'"
echo
echo "🔍 Service status:"
systemctl status oculink-gpu-monitor.service --no-pager -l

echo
echo "⚠️  Important notes:"
echo "   • Always wait for the 'safe to unplug' notification"
echo "   • The system may temporarily restart your compositor"
echo "   • GPU-intensive apps will be closed during removal"