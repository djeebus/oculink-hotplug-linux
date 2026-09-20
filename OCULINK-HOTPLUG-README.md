# OCuLink GPU Hot-Plug Safety System

## Overview
A comprehensive Linux solution for safely hot-plugging OCuLink external GPUs, specifically designed for systems like the GPD Win Max 2. This system provides kernel-level safety, automatic detection, and graceful handling of GPU removal and reconnection.

## Features
- 🔌 **Safe Hot-Removal**: Prepares GPU for safe physical disconnection
- 🔄 **Auto-Reconnection**: Detects and reinitializes GPU when plugged back in
- 🛡️ **Kernel Protection**: Configures kernel to handle surprise removal gracefully
- 🎯 **Two-Stage Detection**: Verifies actual removal before monitoring for reconnection
- 📱 **Desktop Notifications**: Visual feedback throughout the process
- ⌨️ **Keyboard Shortcut**: Single key combo for all operations

## Quick Start

### Installation
```bash
# Run the installer from the directory containing these files
chmod +x install-oculink-hotplug.sh
sudo ./install-oculink-hotplug.sh
```

### Usage
**Keyboard Shortcut**: `SUPER + SHIFT + G`  
**Terminal Command**: `~/gpu-safe-remove` or `/usr/local/bin/gpu-safe-remove`

## Architecture

### Components

#### 1. **gpu-safe-remove** (User Interface)
- Main user-facing script
- Detects GPU state and offers appropriate action
- Provides visual feedback and notifications
- Handles both removal and reconnection workflows

#### 2. **oculink-gpu-manager** (Core Manager)
- Handles the actual GPU preparation process
- Stops GPU processes
- Unloads drivers
- Manages PCIe disconnection
- Triggers monitoring stages

#### 3. **oculink-removal-watcher** (Stage 1 Monitor)
- Waits for physical GPU removal
- Monitors `lspci` to detect when GPU disappears
- Only starts Stage 2 after confirmed removal
- 5-minute timeout with periodic notifications

#### 4. **oculink-reconnect-monitor** (Stage 2 Monitor)
- Monitors for GPU reconnection using udevadm
- Only activates after confirmed removal
- Matches exact GPU model that was removed
- Auto-reinitializes drivers and display
- 10-minute timeout

#### 5. **oculink-kernel-config** (Kernel Safety)
- Runs at boot via systemd
- Configures PCIe ports for hot-plug
- Enables surprise removal handling
- Sets AMDGPU driver resilience parameters
- No bootloader modifications needed

#### 6. **oculink-gpu-watcher** (Health Monitor)
- Background service monitoring GPU health
- Detects GPU errors in kernel log
- Triggers emergency cleanup if needed

### Process Flow

```
User Action (SUPER+SHIFT+G)
    ↓
GPU Detection
    ├─ GPU Present → Offer Removal
    │   ├─ User Confirms
    │   ├─ Stop Processes
    │   ├─ Unload Drivers
    │   ├─ Disconnect PCIe
    │   ├─ Start Stage 1 Monitor
    │   │   ├─ Wait for Physical Removal
    │   │   └─ When Removed → Start Stage 2
    │   └─ Stage 2 Monitor
    │       ├─ Watch for Reconnection
    │       ├─ Detect Same GPU Model
    │       ├─ Reinitialize Drivers
    │       └─ Restart Display
    │
    └─ GPU Absent → Scan for Reconnection
        ├─ Rescan PCIe Bus
        ├─ Detect GPU
        ├─ Load Drivers
        └─ Send Ready Notification
```

## Safety Features

### Multi-GPU Protection
- **Intelligent Detection**: Only targets discrete GPUs (RX 6000/7000 series)
- **Excludes Integrated**: Never touches integrated GPUs (HawkPoint, Vega, etc.)
- **Bus-Based Filtering**: Uses PCIe bus information for accurate targeting

### Kernel-Level Safety
- **PCIe Power Management**: Enables D3cold and ASPM
- **Advanced Error Reporting**: PCIe AER catches disconnection events
- **AMDGPU Recovery**: GPU recovery mode prevents system hangs
- **Timeout Protection**: Driver timeouts prevent infinite waits

### Surprise Removal Handling
- **Automatic Cleanup**: Kills GPU processes on unexpected removal
- **Memory Management**: Clears GPU memory allocations
- **Error Monitoring**: Watches kernel log for PCIe errors
- **Graceful Recovery**: System remains stable even on surprise unplug

## Configuration Files

### Installed Locations
```
/usr/local/bin/
├── gpu-safe-remove           # Main user command
├── oculink-gpu-manager       # Core management logic
├── oculink-removal-watcher   # Stage 1 monitor
├── oculink-reconnect-monitor # Stage 2 monitor
├── oculink-gpu-watcher       # Health monitor
└── oculink-kernel-config     # Kernel configuration

/etc/udev/rules.d/
└── 99-oculink-gpu-hotplug.rules  # Udev rules for GPU events

/etc/systemd/system/
├── oculink-gpu-monitor.service    # GPU health monitoring service
└── oculink-kernel-safety.service  # Kernel configuration service

/var/log/
├── oculink-gpu-manager.log      # Main manager logs
├── oculink-gpu-watcher.log      # Health monitor logs
├── oculink-reconnect.log        # Reconnection monitor logs
└── oculink-removal-watcher.log  # Removal monitor logs
```

### Hyprland Integration
The keyboard shortcut is added to `~/.config/hypr/hyprland.conf`:
```
bind = $mainMod SHIFT, G, exec, ~/gpu-safe-remove  # OCuLink GPU toggle (remove/reconnect)
```

## Monitoring Status

### Check Current State
```bash
# View removal watcher status
[ -f "/tmp/oculink-removal-watcher.pid" ] && echo "Stage 1: Waiting for removal" || echo "Stage 1: Inactive"

# View reconnection monitor status
/usr/local/bin/oculink-reconnect-monitor status

# Check if removal is in progress
[ -f "/tmp/oculink-gpu-removal.lock" ] && echo "Removal in progress" || echo "No removal active"
```

### View Logs
```bash
# Real-time monitoring
tail -f /var/log/oculink-*.log

# Check for errors
grep ERROR /var/log/oculink-*.log

# View kernel messages
dmesg | grep -i "pci\|amdgpu"
```

## Troubleshooting

### GPU Not Detected
1. Check if GPU is visible: `lspci | grep -i vga`
2. Verify it's not filtered as integrated: `lspci | grep -i "RX 6"`
3. Check logs: `tail /var/log/oculink-gpu-manager.log`

### Removal Not Working
1. Check for lock file: `ls -la /tmp/oculink-*.lock`
2. Clear stuck state: `rm -f /tmp/oculink-*.lock /tmp/oculink-*.pid`
3. Restart services: `sudo systemctl restart oculink-gpu-monitor`

### Reconnection Not Detected
1. Manual rescan: `echo 1 | sudo tee /sys/bus/pci/rescan`
2. Check monitor status: `/usr/local/bin/oculink-reconnect-monitor status`
3. Verify GPU model matches: `cat /tmp/oculink-removed-gpu`

### System Hangs on Removal
1. Kernel safety not active: `sudo systemctl status oculink-kernel-safety`
2. Start kernel config: `sudo /usr/local/bin/oculink-kernel-config`
3. Check AMDGPU parameters: `cat /sys/module/amdgpu/parameters/gpu_recovery`

## Advanced Usage

### Manual Operations
```bash
# Force safe removal (bypasses prompts)
echo "y" | ~/gpu-safe-remove

# Cancel removal in progress
pkill -f oculink-removal-watcher
rm -f /tmp/oculink-*.lock

# Manually trigger reconnection scan
sudo sh -c 'echo 1 > /sys/bus/pci/rescan'

# Stop all monitoring
sudo systemctl stop oculink-gpu-monitor
pkill -f oculink-reconnect-monitor
pkill -f oculink-removal-watcher
```

### Custom Hooks
Create scripts that run on GPU events:
```bash
# Post-reconnection hook
~/.config/scripts/gpu-reconnected.sh

# Pre-removal hook (add to oculink-gpu-manager)
~/.config/scripts/gpu-pre-remove.sh
```

## Compatibility

### Tested Systems
- **GPD Win Max 2**: Full compatibility with OCuLink port
- **AMD GPUs**: RX 6000/7000 series
- **Integrated GPUs**: Safely excluded (HawkPoint, Vega, etc.)

### Requirements
- Linux kernel 5.10+ (PCIe hot-plug support)
- systemd (service management)
- udev (device event handling)
- libnotify (desktop notifications)
- AMDGPU driver

### Known Limitations
- OCuLink power delivery varies by dock/enclosure
- Some systems may not support full hot-plug at BIOS level
- GPU must be idle for cleanest removal

## Safety Warnings

⚠️ **Important**:
1. Always wait for "Safe to Unplug" notification
2. Don't remove GPU during heavy load or high temperatures
3. Use quality OCuLink cables and enclosures
4. Save work before testing first removal
5. Kernel safety helps but isn't 100% guaranteed

## Contributing

Report issues or improvements:
- Logs: Include `/var/log/oculink-*.log` files
- System: Specify GPU model and system details
- Steps: Describe exact sequence leading to issue

## License

This system is provided as-is for the Linux community. Use at your own risk. The authors are not responsible for hardware damage or data loss.

---

*Created for safe OCuLink GPU hot-plugging on Linux systems*