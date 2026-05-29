#!/bin/bash
# =======================================================================
# ProxmoxInfra – Raspberry Pi Setup Script
# =======================================================================
# Sets up the Raspberry Pi as a ZeroTier VPN node and Wake-on-LAN proxy.
#
# What this script does:
#   1. Updates the system
#   2. Installs ZeroTier-One (official install script)
#   3. Installs wakeonlan and etherwake
#   4. Installs Python3 and Flask for the WOL REST API
#   5. Prompts for ZeroTier Network ID and joins the network
#   6. Prompts for Proxmox host MAC address and saves to config
#   7. Installs and enables the WOL API systemd service
#   8. Prints the ZeroTier node ID and instructions
#
# Usage:
#   chmod +x setup.sh
#   sudo ./setup.sh
#
# This script is idempotent — safe to run multiple times.
# =======================================================================

set -e

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Colour

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WOL_CONFIG_DIR="/etc/wol"
WOL_CONFIG_FILE="${WOL_CONFIG_DIR}/proxmox.conf"
WOL_API_ENV_FILE="${WOL_CONFIG_DIR}/wol-api.env"
SERVICE_FILE="/etc/systemd/system/wol-api.service"

print_step() {
    echo -e "\n${CYAN}==> $1${NC}"
}

print_ok() {
    echo -e "    ${GREEN}[OK]${NC} $1"
}

print_warn() {
    echo -e "    ${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "    ${RED}[ERROR]${NC} $1"
}

# -----------------------------------------------------------------------
# Must run as root
# -----------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root: sudo ./setup.sh"
    exit 1
fi

echo ""
echo "========================================"
echo "  ProxmoxInfra Raspberry Pi Setup"
echo "========================================"

# -----------------------------------------------------------------------
# Step 1: System update
# -----------------------------------------------------------------------
print_step "Updating package lists..."
apt-get update -qq
print_ok "Package lists updated"

print_step "Upgrading installed packages..."
apt-get upgrade -y -qq
print_ok "Packages upgraded"

# -----------------------------------------------------------------------
# Step 2: Install ZeroTier
# -----------------------------------------------------------------------
print_step "Checking ZeroTier installation..."
if command -v zerotier-cli &>/dev/null; then
    ZT_VERSION=$(zerotier-cli -v 2>/dev/null || echo "unknown")
    print_ok "ZeroTier already installed (${ZT_VERSION})"
else
    print_step "Installing ZeroTier-One..."
    curl -s https://install.zerotier.com | bash
    print_ok "ZeroTier installed"
fi

# Enable and start ZeroTier
systemctl enable zerotier-one --quiet
systemctl start  zerotier-one
print_ok "ZeroTier service enabled and started"

# -----------------------------------------------------------------------
# Step 3: Install WOL tools
# -----------------------------------------------------------------------
print_step "Installing Wake-on-LAN tools (wakeonlan, etherwake)..."
if ! dpkg -l wakeonlan &>/dev/null; then
    apt-get install -y -qq wakeonlan
    print_ok "wakeonlan installed"
else
    print_ok "wakeonlan already installed"
fi

if ! dpkg -l etherwake &>/dev/null; then
    apt-get install -y -qq etherwake
    print_ok "etherwake installed"
else
    print_ok "etherwake already installed"
fi

# -----------------------------------------------------------------------
# Step 4: Install Python3 and Flask
# -----------------------------------------------------------------------
print_step "Checking Python3 and Flask..."
if ! command -v python3 &>/dev/null; then
    apt-get install -y -qq python3 python3-pip
    print_ok "Python3 installed"
else
    print_ok "Python3 already installed ($(python3 --version))"
fi

if ! python3 -c "import flask" &>/dev/null 2>&1; then
    print_step "Installing Flask..."
    # Try apt first (avoids pip externally-managed error on newer Raspi OS)
    if apt-get install -y -qq python3-flask 2>/dev/null; then
        print_ok "Flask installed via apt"
    else
        pip3 install flask --quiet
        print_ok "Flask installed via pip"
    fi
else
    print_ok "Flask already installed"
fi

# Also install wakeonlan Python package for the API
if ! python3 -c "import wakeonlan" &>/dev/null 2>&1; then
    apt-get install -y -qq python3-wakeonlan 2>/dev/null || pip3 install wakeonlan --quiet
    print_ok "python3-wakeonlan installed"
else
    print_ok "python3-wakeonlan already installed"
fi

# -----------------------------------------------------------------------
# Step 5: Join ZeroTier network
# -----------------------------------------------------------------------
print_step "ZeroTier Network Setup"
echo ""

# Check if already in a network
EXISTING_NETWORKS=$(zerotier-cli listnetworks 2>/dev/null | grep -v "^200" | grep -v "^==" | tail -n +2 || true)

if [ -n "$EXISTING_NETWORKS" ]; then
    echo "    Already joined ZeroTier networks:"
    echo "$EXISTING_NETWORKS" | while read -r line; do
        echo "      $line"
    done
    echo ""
    read -rp "    Enter ZeroTier Network ID to join (or press Enter to skip): " ZT_NETWORK_ID
else
    read -rp "    Enter your ZeroTier Network ID (16 hex chars, e.g. a09acf0233abcdef): " ZT_NETWORK_ID
fi

if [ -n "$ZT_NETWORK_ID" ]; then
    if [[ "$ZT_NETWORK_ID" =~ ^[0-9a-fA-F]{16}$ ]]; then
        zerotier-cli join "$ZT_NETWORK_ID"
        print_ok "Joined ZeroTier network: $ZT_NETWORK_ID"
        echo ""
        echo -e "    ${YELLOW}ACTION REQUIRED:${NC} Authorize this node in ZeroTier Central:"
        echo "      https://my.zerotier.com → your network → Members tab"
        echo "      Assign managed IP: 172.22.0.1"
    else
        print_warn "Invalid Network ID format. Skipping ZeroTier join."
        print_warn "Run manually: sudo zerotier-cli join <NETWORK_ID>"
    fi
else
    print_warn "No Network ID provided. Skipping ZeroTier join."
    print_warn "Run manually: sudo zerotier-cli join <NETWORK_ID>"
fi

# -----------------------------------------------------------------------
# Step 6: Save Proxmox host MAC address
# -----------------------------------------------------------------------
print_step "Wake-on-LAN Configuration"

mkdir -p "$WOL_CONFIG_DIR"
chmod 755 "$WOL_CONFIG_DIR"

if [ -f "$WOL_CONFIG_FILE" ]; then
    EXISTING_MAC=$(grep '^MAC=' "$WOL_CONFIG_FILE" | cut -d= -f2 || true)
    if [ -n "$EXISTING_MAC" ]; then
        echo "    Existing Proxmox MAC address: $EXISTING_MAC"
        read -rp "    Enter new MAC address (or press Enter to keep existing): " NEW_MAC
        if [ -n "$NEW_MAC" ]; then
            PROXMOX_MAC="$NEW_MAC"
        else
            PROXMOX_MAC="$EXISTING_MAC"
        fi
    else
        read -rp "    Enter Proxmox host MAC address (e.g. aa:bb:cc:dd:ee:ff): " PROXMOX_MAC
    fi
else
    echo "    Find the Proxmox host NIC MAC address with: ip link show"
    read -rp "    Enter Proxmox host MAC address (e.g. aa:bb:cc:dd:ee:ff): " PROXMOX_MAC
fi

if [ -n "$PROXMOX_MAC" ]; then
    if [[ "$PROXMOX_MAC" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
        echo "MAC=${PROXMOX_MAC}" > "$WOL_CONFIG_FILE"
        chmod 600 "$WOL_CONFIG_FILE"
        print_ok "Saved MAC address to $WOL_CONFIG_FILE"
    else
        print_warn "Invalid MAC format. Skipping. Run manually:"
        print_warn "  echo 'MAC=aa:bb:cc:dd:ee:ff' | sudo tee $WOL_CONFIG_FILE"
    fi
else
    print_warn "No MAC address provided. WOL will not work until configured."
    print_warn "Set it later: echo 'MAC=aa:bb:cc:dd:ee:ff' | sudo tee $WOL_CONFIG_FILE"
fi

# -----------------------------------------------------------------------
# Step 7: Configure WOL API key
# -----------------------------------------------------------------------
print_step "WOL API Security Configuration"

if [ -f "$WOL_API_ENV_FILE" ]; then
    EXISTING_KEY=$(grep '^API_KEY=' "$WOL_API_ENV_FILE" | cut -d= -f2 || true)
    if [ -n "$EXISTING_KEY" ]; then
        print_ok "API key already configured (keeping existing)"
        API_KEY="$EXISTING_KEY"
    fi
fi

if [ -z "${API_KEY:-}" ]; then
    read -rp "    Enter a secret API key for the WOL HTTP API (or press Enter to auto-generate): " API_KEY_INPUT
    if [ -n "$API_KEY_INPUT" ]; then
        API_KEY="$API_KEY_INPUT"
    else
        API_KEY=$(openssl rand -hex 24 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(24))")
        echo "    Auto-generated API key: ${YELLOW}${API_KEY}${NC}"
        echo "    (Save this — you will need it to call the WOL API)"
    fi

    {
        echo "API_KEY=${API_KEY}"
        echo "WOL_CONFIG=${WOL_CONFIG_FILE}"
    } > "$WOL_API_ENV_FILE"
    chmod 600 "$WOL_API_ENV_FILE"
    print_ok "API key saved to $WOL_API_ENV_FILE"
fi

# -----------------------------------------------------------------------
# Step 8: Install WOL API systemd service
# -----------------------------------------------------------------------
print_step "Installing WOL API systemd service..."

WOL_API_SCRIPT="${SCRIPT_DIR}/wake-on-lan/wol-api.py"

if [ ! -f "$WOL_API_SCRIPT" ]; then
    print_warn "wol-api.py not found at $WOL_API_SCRIPT"
    print_warn "Service will be installed but may not start until wol-api.py is present."
fi

# Copy service file if it exists in the repo
if [ -f "${SCRIPT_DIR}/wake-on-lan/wol-api.service" ]; then
    cp "${SCRIPT_DIR}/wake-on-lan/wol-api.service" "$SERVICE_FILE"
    # Update the path to wol-api.py in the service file
    sed -i "s|ExecStart=.*|ExecStart=/usr/bin/python3 ${WOL_API_SCRIPT}|g" "$SERVICE_FILE"
    print_ok "Service file installed to $SERVICE_FILE"
else
    print_warn "wol-api.service not found — writing default service file..."
    cat > "$SERVICE_FILE" << SERVICEEOF
[Unit]
Description=Wake-on-LAN REST API
After=network.target zerotier-one.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${WOL_API_SCRIPT}
EnvironmentFile=${WOL_API_ENV_FILE}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEEOF
    print_ok "Default service file created"
fi

systemctl daemon-reload
systemctl enable wol-api --quiet

# Only start if the script exists
if [ -f "$WOL_API_SCRIPT" ]; then
    systemctl restart wol-api
    print_ok "WOL API service started"
else
    print_warn "WOL API service enabled but not started (wol-api.py missing)"
fi

# -----------------------------------------------------------------------
# Step 9: Make wol.sh executable
# -----------------------------------------------------------------------
WOL_SCRIPT="${SCRIPT_DIR}/wake-on-lan/wol.sh"
if [ -f "$WOL_SCRIPT" ]; then
    chmod +x "$WOL_SCRIPT"
    print_ok "Made $WOL_SCRIPT executable"
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
ZT_NODE_ID=$(zerotier-cli info 2>/dev/null | awk '{print $3}' || echo "unknown")

echo ""
echo "========================================"
echo -e "${GREEN}  Raspberry Pi Setup Complete!${NC}"
echo "========================================"
echo ""
echo "  ZeroTier Node ID:   ${CYAN}${ZT_NODE_ID}${NC}"
echo "  ZeroTier Status:    $(zerotier-cli status 2>/dev/null | awk '{print $4}' || echo 'check: sudo zerotier-cli status')"
echo ""
echo -e "  ${YELLOW}REQUIRED NEXT STEPS:${NC}"
echo "  1. Authorize this node in ZeroTier Central:"
echo "       https://my.zerotier.com → your network → Members"
echo "     - Check the 'Auth' checkbox for node: ${ZT_NODE_ID}"
echo "     - Assign managed IP: 172.22.0.1"
echo ""
echo "  2. Install ZeroTier on your workstation and join the same network"
echo "       Assign it managed IP: 172.22.0.2"
echo ""
echo "  3. Test WOL from this Raspi:"
echo "       ${WOL_SCRIPT}"
echo ""
echo "  4. Test WOL API (from workstation over ZeroTier):"
echo "       curl -X POST http://172.22.0.1:8080/wake \\"
echo "            -H 'X-API-Key: <your_api_key>'"
echo ""
echo "  WOL API key saved at: ${WOL_API_ENV_FILE}"
echo "  Proxmox MAC saved at: ${WOL_CONFIG_FILE}"
echo ""
