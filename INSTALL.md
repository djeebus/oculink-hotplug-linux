# OCuLink Hot-Plug System Installation Guide

## Quick Install

From the `~/oculink-hotplug-system` directory:

```bash
cd ~/oculink-hotplug-system
sudo ./install-oculink-hotplug.sh
```

## Manual Installation

If you prefer to install components individually:

### 1. Copy Scripts
```bash
sudo cp gpu-safe-remove /usr/local/bin/
sudo cp oculink-gpu-manager /usr/local/bin/
sudo cp oculink-gpu-watcher /usr/local/bin/
sudo cp oculink-reconnect-monitor /usr/local/bin/
sudo cp oculink-removal-watcher /usr/local/bin/
sudo cp oculink-kernel-config /usr/local/bin/
sudo chmod +x /usr/local/bin/oculink-*
sudo chmod +x /usr/local/bin/gpu-safe-remove
sudo install -D -m 644 oculink-common.sh /usr/local/lib/oculink/oculink-common.sh
sudo install -m 644 oculink-gpu.conf /etc/
```

Edit `oculink-gpu.conf` to change which PCI vendor/class/device IDs are treated as the OCuLink GPU.

### 2. Install udev Rules
```bash
sudo cp 99-oculink-gpu-hotplug.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### 3. Install systemd Services
```bash
sudo cp oculink-gpu-monitor.service /etc/systemd/system/
sudo cp oculink-kernel-safety.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now oculink-gpu-monitor.service
sudo systemctl enable --now oculink-kernel-safety.service
```

### 4. Setup User Access
```bash
# Copy to home for easy access
cp gpu-safe-remove ~/
chmod +x ~/gpu-safe-remove
```

## Verify Installation

```bash
# Check services are running
systemctl status oculink-gpu-monitor
systemctl status oculink-kernel-safety

# Test the command
~/gpu-safe-remove
```

## Keyboard Shortcut

The Hyprland keybind (SUPER+SHIFT+G) is already configured in your `~/.config/hypr/hyprland.conf`

## Uninstall

```bash
# Stop services
sudo systemctl stop oculink-gpu-monitor oculink-kernel-safety
sudo systemctl disable oculink-gpu-monitor oculink-kernel-safety

# Remove files
sudo rm -f /usr/local/bin/{gpu-safe-remove,oculink-*}
sudo rm -rf /usr/local/lib/oculink
sudo rm -f /etc/oculink-gpu.conf
sudo rm -f /etc/udev/rules.d/99-oculink-gpu-hotplug.rules
sudo rm -f /etc/systemd/system/oculink-*.service

# Reload
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
```

## Important Files

Keep this directory (`~/oculink-hotplug-system/`) as your backup. It contains:
- All source scripts
- Documentation
- Installation scripts
- Service definitions

**DO NOT DELETE THIS DIRECTORY** - It's your master copy!