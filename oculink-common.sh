# Shared helpers for the oculink-* scripts. Source this file; don't run it.
# Installed to /usr/local/lib/oculink/oculink-common.sh

OCULINK_CONF="${OCULINK_CONF:-/etc/oculink-gpu.conf}"
if [ ! -r "$OCULINK_CONF" ]; then
    # Fall back to the copy next to this file (running from a checkout)
    OCULINK_CONF="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/oculink-gpu.conf"
fi
if ! source "$OCULINK_CONF" 2>/dev/null; then
    echo "oculink: cannot read GPU config ($OCULINK_CONF)" >&2
    exit 1
fi

# Sibling scripts live next to whichever script sourced us (/usr/local/bin, or a checkout)
OCULINK_BIN_DIR="$(dirname -- "$(readlink -f -- "$0")")"

# State shared between the scripts while a removal is in progress
OCULINK_RUN_DIR="/run/oculink"
OCULINK_LOCKFILE="$OCULINK_RUN_DIR/removal.lock"
OCULINK_REMOVED_GPU_FILE="$OCULINK_RUN_DIR/removed-gpu"
OCULINK_REMOVED_PORT_FILE="$OCULINK_RUN_DIR/removed-port"
OCULINK_PORT_POWER_FILE="$OCULINK_RUN_DIR/port-power-control"
mkdir -p "$OCULINK_RUN_DIR" 2>/dev/null

# systemd units the background stages run as, so udev/sudo exiting can't kill them
OCULINK_REMOVAL_UNIT="oculink-removal-watcher"
OCULINK_RECONNECT_UNIT="oculink-reconnect-monitor"

# Print "<pci address> <description>" for each OCuLink GPU on the bus, e.g.
#   0000:c6:00.0 Advanced Micro Devices, Inc. [AMD/ATI] Navi 31 [...] (rev c8)
list_oculink_gpus() {
    local class device
    for class in $GPU_PCI_CLASSES; do
        for device in ${GPU_DEVICE_IDS:-any}; do
            [ "$device" = "any" ] && device=""
            lspci -D -d "${GPU_VENDOR_ID}:${device}:${class}"
        done
    done | sed 's/^\([^ ]*\) [^:]*: /\1 /' | sort -u
}

# Print the PCI address (e.g. 0000:c6:00.0) of each OCuLink GPU on the bus
find_oculink_gpus() {
    list_oculink_gpus | cut -d' ' -f1
}

# True if the given IDs match the config. Accepts hex with or without 0x, and
# the class as either 4 digits (0300) or the full code (030000, 0x030000, or
# 30000 as udev's PCI_CLASS drops the leading zero).
is_oculink_gpu_id() {
    local vendor="${1#0x}" device="${2#0x}" class="${3#0x}" d
    vendor="${vendor,,}"
    device="${device,,}"
    [ ${#class} -le 4 ] && class="${class}00"
    printf -v class '%06x' "$((16#$class))"
    class="${class:0:4}"

    [ "$vendor" = "${GPU_VENDOR_ID,,}" ] || return 1
    [[ " $GPU_PCI_CLASSES " == *" $class "* ]] || return 1
    [ -z "$GPU_DEVICE_IDS" ] && return 0
    for d in $GPU_DEVICE_IDS; do
        [ "$device" = "${d,,}" ] && return 0
    done
    return 1
}

# True if the PCI device at the given address (e.g. 0000:c6:00.0) matches the config
is_oculink_gpu() {
    local dev="/sys/bus/pci/devices/$1"
    [ -r "$dev/vendor" ] || return 1
    is_oculink_gpu_id "$(<"$dev/vendor")" "$(<"$dev/device")" "$(<"$dev/class")"
}

# Print the PCIe port the GPU's card is plugged into (e.g. 0000:00:03.1).
# Climbs past bridges that belong to the card itself (Navi cards have an
# internal switch with the GPU's vendor ID), so everything below the port is
# the card: a PCIe port has a single link, so it only has the one device.
oculink_card_port() {
    local dev parent
    dev=$(readlink -f "/sys/bus/pci/devices/$1") || return 1
    while true; do
        parent=$(dirname "$dev")
        [ -r "$parent/vendor" ] || return 1  # on the host bridge: not behind a port
        # Stop at the root port (its parent is the host bridge, not a PCI device)
        if [ "$(<"$parent/vendor")" = "0x${GPU_VENDOR_ID,,}" ] && [ -r "$(dirname "$parent")/vendor" ]; then
            dev="$parent"
        else
            basename "$parent"
            return 0
        fi
    done
}

# Print how link state is read for the given port: "dllla" if it reports the
# Data Link Layer Link Active bit (needs root to read), otherwise "width"
oculink_link_method() {
    local lnkcap
    lnkcap=$(setpci -s "$1" CAP_EXP+0x0c.l 2>/dev/null)
    if [[ "$lnkcap" =~ ^[0-9a-fA-F]+$ ]] && (( 16#$lnkcap & (1 << 20) )); then
        echo dllla
    else
        echo width
    fi
}

# True if the PCIe link below the given port is up, i.e. a card is physically
# attached. Prefers the Data Link Layer Link Active bit, falling back to the
# negotiated link width.
oculink_link_up() {
    local lnksta width
    if [ "$(oculink_link_method "$1")" = "dllla" ]; then
        lnksta=$(setpci -s "$1" CAP_EXP+0x12.w 2>/dev/null)
        [[ "$lnksta" =~ ^[0-9a-fA-F]+$ ]] && (( 16#$lnksta & (1 << 13) ))
        return
    fi
    width=$(cat "/sys/bus/pci/devices/$1/current_link_width" 2>/dev/null)
    [[ "$width" =~ ^[0-9]+$ ]] && [ "$width" -gt 0 ]
}

# Print PIDs of processes holding the GPU's DRM nodes (/dev/dri/card*, renderD*) open
oculink_gpu_pids() {
    local n nodes=()
    for n in /sys/bus/pci/devices/"$1"/drm/card* /sys/bus/pci/devices/"$1"/drm/renderD*; do
        [ -e "/dev/dri/${n##*/}" ] && nodes+=("/dev/dri/${n##*/}")
    done
    [ ${#nodes[@]} -gt 0 ] || return 0
    fuser "${nodes[@]}" 2>/dev/null | tr -s ' \t' '\n' | grep -E '^[0-9]+$' | sort -un
}

# Print the GPU's display connectors that have a display attached (e.g. DP-3).
# Removing the GPU with displays attached can panic the kernel: amdgpu tears
# down DP MST hubs/daisy chains after the display hardware is already gone
# (NULL deref in dc_link_aux_transfer_raw from amdgpu_dm_connector_destroy).
oculink_gpu_displays() {
    local c name
    for c in /sys/bus/pci/devices/"$1"/drm/card*/card*-*; do
        name="${c##*/}"
        [ "$(cat "$c/status" 2>/dev/null)" = "connected" ] && echo "${name#card*-}"
    done
    return 0
}

# Processes that hold GPU fds on behalf of the session (logind opens DRM
# devices for the compositor, and parks copies in PID 1's fd store). Killing
# them takes down the session or the system, so they're spared regardless of
# GPU_SPARE_PROCESSES.
OCULINK_ALWAYS_SPARED="systemd systemd-logind"

# True if the process (pid, name) should never be killed
oculink_is_spared() {
    [ "$1" = "1" ] && return 0
    [[ " $OCULINK_ALWAYS_SPARED $GPU_SPARE_PROCESSES " == *" $2 "* ]]
}

# Rescan the port the GPU was removed from (the whole bus if unknown).
# True if the GPU is back afterwards.
oculink_rescan() {
    local port
    port=$(cat "$OCULINK_REMOVED_PORT_FILE" 2>/dev/null)
    if [ -n "$port" ] && [ -e "/sys/bus/pci/devices/$port/rescan" ]; then
        echo 1 > "/sys/bus/pci/devices/$port/rescan"
    else
        echo 1 > /sys/bus/pci/rescan
    fi
    sleep 2
    [ -n "$(find_oculink_gpus)" ]
}

# Undo the removal: restore the port's power management and clear the state files
oculink_clear_removal_state() {
    local port power
    port=$(cat "$OCULINK_REMOVED_PORT_FILE" 2>/dev/null)
    power=$(cat "$OCULINK_PORT_POWER_FILE" 2>/dev/null)
    if [ -n "$port" ] && [ -n "$power" ]; then
        echo "$power" > "/sys/bus/pci/devices/$port/power/control" 2>/dev/null
    fi
    rm -f "$OCULINK_LOCKFILE" "$OCULINK_REMOVED_GPU_FILE" "$OCULINK_REMOVED_PORT_FILE" "$OCULINK_PORT_POWER_FILE"
}

# The user logged in on the local seat (for notifications)
oculink_desktop_user() {
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        echo "$SUDO_USER"
        return
    fi
    loginctl list-sessions --no-legend 2>/dev/null | awk '$4 ~ /^seat/ {print $3; exit}'
}

# Desktop notification to the logged-in user. Root has no session bus of its
# own, so point notify-send at the user's.
notify_user() {
    local title="$1" message="$2" urgency="${3:-normal}" app="${4:-OCuLink GPU}" user uid
    user=$(oculink_desktop_user)
    [ -n "$user" ] && uid=$(id -u "$user" 2>/dev/null) || return 0
    if [ "$EUID" -eq "$uid" ]; then
        notify-send --urgency="$urgency" --app-name="$app" "$title" "$message" 2>/dev/null
    else
        runuser -u "$user" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            notify-send --urgency="$urgency" --app-name="$app" "$title" "$message" 2>/dev/null
    fi
    return 0
}
