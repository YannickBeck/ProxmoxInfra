#!/bin/bash
# Send Wake-on-LAN magic packet to Proxmox host
# Usage: ./wol.sh [MAC_ADDRESS]
# MAC can be set in /etc/wol/proxmox.conf as MAC=xx:xx:xx:xx:xx:xx

CONFIG_FILE="/etc/wol/proxmox.conf"
MAC="${1}"

if [ -z "$MAC" ] && [ -f "$CONFIG_FILE" ]; then
    MAC=$(grep '^MAC=' "$CONFIG_FILE" | cut -d= -f2)
fi

if [ -z "$MAC" ]; then
    echo "Usage: $0 <MAC_ADDRESS>"
    echo "Or set MAC= in $CONFIG_FILE"
    exit 1
fi

if command -v wakeonlan &>/dev/null; then
    wakeonlan "$MAC"
elif command -v etherwake &>/dev/null; then
    sudo etherwake "$MAC"
else
    echo "Neither wakeonlan nor etherwake found. Run: sudo apt install wakeonlan"
    exit 1
fi

echo "Magic packet sent to $MAC"
