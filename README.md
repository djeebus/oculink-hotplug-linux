# 🔌 OCuLink GPU Hot-Plug for Linux

Safe hot-plugging system for OCuLink external GPUs on Linux, designed for devices like GPD Win Max 2.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Linux](https://img.shields.io/badge/platform-Linux-orange.svg)
![AMD GPU](https://img.shields.io/badge/GPU-AMD-red.svg)

## ✨ Features

- **🛡️ Safe Removal** - Gracefully prepares GPU for disconnection
- **🔄 Auto-Reconnection** - Detects and reinitializes GPU when reconnected
- **🧠 Smart Detection** - Two-stage monitoring system
- **⚡ Fake Hotplug** - Watches the OCuLink port's link state, since OCuLink has no hotplug signalling
- **🎮 Multi-GPU Support** - Safely handles systems with integrated + discrete GPUs
- **📱 Desktop Integration** - Notifications and keyboard shortcuts

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/yourusername/oculink-hotplug-linux
cd oculink-hotplug-linux

# Install the system
sudo ./install-oculink-hotplug.sh

# Use the keyboard shortcut
# SUPER + SHIFT + G
```

## 📖 Documentation

- [Full Documentation](OCULINK-HOTPLUG-README.md) - Complete system guide
- [Installation Guide](INSTALL.md) - Detailed installation instructions

## 🎯 Usage

### Keyboard Shortcut
Press `SUPER + SHIFT + G` to toggle GPU removal/reconnection

### Terminal
```bash
~/gpu-safe-remove
```

### What Happens
1. **Removal**: Safely prepares GPU → Waits for unplug → Monitors for reconnection
2. **Reconnection**: Detects the link coming back → Rescans the port → Ready!

## 🔧 System Requirements

- Linux kernel 5.10+
- systemd
- AMD GPU (RX 6000/7000 series tested)
- OCuLink port or eGPU enclosure

## ⚠️ Safety Warning

While this system adds multiple safety layers, OCuLink hot-plugging is not officially supported by all hardware. Use at your own risk. Always:
- Wait for "Safe to Unplug" notification
- Avoid removal under heavy GPU load
- Use quality OCuLink cables and enclosures

## 🤝 Contributing

Contributions welcome! Please test thoroughly and document any hardware-specific quirks.

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details

## 🙏 Acknowledgments

Created for the Linux eGPU community, especially GPD Win Max 2 users.

---

**⭐ If this helps you, please star the repository!**