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
- Closes programs holding the GPU's `/dev/dri` nodes open (compositors are spared; see `GPU_SPARE_PROCESSES`)
- Removes the whole card (GPU, HDMI audio, and the card's internal PCIe switch) from the bus, leaving `amdgpu` loaded for the iGPU
- Triggers monitoring stages
- `oculink-gpu-manager status` shows the GPU, its port, link state, and which programs would be closed

OCuLink ports have no hotplug signalling, so the kernel never notices the cable
being pulled or plugged back in. Both stages instead poll the link state of the
PCIe port the card hangs off (the Data Link Layer Link Active bit, or the link
width if the port can't report that), and run as transient systemd units so
they outlive the command that started them.

#### 3. **oculink-removal-watcher** (Stage 1 Monitor)
- Waits for physical GPU removal by watching the port's link go down
- Only starts Stage 2 after confirmed removal
- 5-minute timeout with periodic notifications; on timeout the GPU is restored

#### 4. **oculink-reconnect-monitor** (Stage 2 Monitor)
- Watches the port's link come back up, then rescans just that port
- Only activates after confirmed removal
- Matches exact GPU model that was removed
- 10-minute timeout (after that, run `gpu-safe-remove` to rescan)

#### 5. **oculink-kernel-config** (PCIe Configuration)
- Runs at boot via systemd
- Enables runtime power management for the GPU
- No bootloader modifications needed

#### 6. **oculink-gpu-watcher** (Health Monitor)
- Follows the kernel log for errors from the OCuLink GPU
- Notifies you (at most once a minute); doesn't remove the GPU itself

### Process Flow

```
User Action (SUPER+SHIFT+G)
    ↓
GPU Detection
    ├─ GPU Present → Offer Removal
    │   ├─ User Confirms
    │   ├─ Close Programs Using the GPU
    │   ├─ Remove Card from PCIe Bus
    │   ├─ Start Stage 1 Monitor
    │   │   ├─ Wait for Port Link Down (Physical Removal)
    │   │   └─ When Removed → Start Stage 2
    │   └─ Stage 2 Monitor
    │       ├─ Wait for Port Link Up (Reconnection)
    │       ├─ Rescan the Port
    │       └─ Detect Same GPU Model
    │
    ├─ Removal In Progress → Offer to Cancel (Rescan to Restore GPU)
    │
    └─ GPU Absent → Scan for Reconnection
        ├─ Rescan the Port (or Whole Bus)
        ├─ Detect GPU
        ├─ Load Drivers
        └─ Send Ready Notification
```

## Safety Features

### Multi-GPU Protection
- **ID-Based Detection**: Matches the GPU by PCI vendor ID, class, and (optionally) device ID from `/etc/oculink-gpu.conf`
- **Excludes Integrated**: AMD APU iGPUs that report the Display controller class (0380) are never matched; pin `GPU_DEVICE_IDS` if your iGPU uses VGA class 0300

### Removal Safety
- **Targeted Process Cleanup**: Only programs with the eGPU open are closed (SIGTERM, then SIGKILL after 10s)
- **Session Preserved**: The compositor keeps running; only the eGPU's displays go away
- **Whole-Card Removal**: The GPU's audio function and bridges are removed too, so nothing is left attached when the cable is pulled
- **Port Kept Powered**: Runtime PM is disabled on the port while it's empty so link state stays accurate, and restored on reconnect
- **Error Monitoring**: Watches kernel log for errors from the eGPU

Unplugging without running `gpu-safe-remove` first is still a surprise removal, which this can't make safe.

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

/usr/local/lib/oculink/
└── oculink-common.sh         # Shared GPU detection helpers

/etc/
└── oculink-gpu.conf          # PCI vendor/class/device IDs to treat as the OCuLink GPU

/etc/udev/rules.d/
└── 99-oculink-gpu-hotplug.rules  # Runs the manager when the GPU appears after a rescan

/run/oculink/                     # State while a removal is in progress (lock, port, GPU model)

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
# GPU, port, link state, and removal state
sudo oculink-gpu-manager status

# View removal watcher (Stage 1) status
systemctl status oculink-removal-watcher

# View reconnection monitor (Stage 2) status
oculink-reconnect-monitor status
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
1. Check if GPU is visible, with IDs: `lspci -nn | grep -Ei 'vga|3d|display'`
2. Compare its `[class]` and `[vendor:device]` against `/etc/oculink-gpu.conf`
3. Check logs: `tail /var/log/oculink-gpu-manager.log`

### Removal Not Working
1. Check state: `sudo oculink-gpu-manager status`
2. Cancel a stuck removal: run `gpu-safe-remove` and choose to cancel
3. Check logs: `tail /var/log/oculink-gpu-manager.log /var/log/oculink-removal-watcher.log`

### Unplug Not Detected
Stage 1 relies on the port's link going down. With the GPU removed and the
cable unplugged, `sudo oculink-gpu-manager status` should show `Link: down`.
If it still shows `up`, your port doesn't report link state and the watcher
will time out and restore the GPU after 5 minutes.

### Reconnection Not Detected
1. Run `gpu-safe-remove` again; with no GPU present it rescans
2. Check monitor status: `oculink-reconnect-monitor status`
3. Verify GPU model matches: `cat /run/oculink/removed-gpu`

## Advanced Usage

### Manual Operations
```bash
# Force safe removal (bypasses prompts)
echo "y" | ~/gpu-safe-remove

# Cancel removal in progress (restores the GPU)
echo "y" | ~/gpu-safe-remove

# Manually trigger reconnection scan
sudo sh -c 'echo 1 > /sys/bus/pci/rescan'

# Stop all monitoring
sudo systemctl stop oculink-gpu-monitor oculink-removal-watcher oculink-reconnect-monitor
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
- **Integrated GPUs**: Excluded via `/etc/oculink-gpu.conf` (Strix Point reports class 0380 and is skipped by default)

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