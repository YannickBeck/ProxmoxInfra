#!/bin/bash
# =======================================================================
# join-zerotier.sh  –  Gerät dem ProxmoxInfra-Lab-Netzwerk hinzufügen
# =======================================================================
# Installiert ZeroTier-One (falls noch nicht vorhanden) und tritt dem
# Lab-Netzwerk bei. Funktioniert auf Raspberry Pi OS, Debian/Ubuntu und
# anderen APT-basierten Linux-Distributionen sowie auf RHEL/Rocky/CentOS.
#
# Netzwerk-ID: 4753cf475fdd8c73
#
# Empfohlene verwaltete IPs (in ZeroTier Central zuweisen):
#   172.22.0.1  –  Raspberry Pi (Always-on-Gateway)
#   172.22.0.2  –  Workstation
#   172.22.0.3  –  Proxmox Host (optional)
#   172.22.0.4  –  weiteres Gerät
#
# Verwendung:
#   chmod +x join-zerotier.sh
#   sudo ./join-zerotier.sh [--ip <172.22.0.X>] [--name <Gerätename>]
#
# Flags:
#   --ip <IP>    Empfohlene ZeroTier-IP (nur zur Anzeige; muss in
#                ZeroTier Central manuell zugewiesen werden)
#   --name <n>   Gerätename (nur für die Ausgabe; optional)
#   --dry-run    Zeigt an was ausgeführt werden würde, ohne Änderungen
# =======================================================================

set -euo pipefail

# -----------------------------------------------------------------------
# Konstanten
# -----------------------------------------------------------------------
readonly ZT_NETWORK_ID="4753cf475fdd8c73"
readonly ZT_CENTRAL_URL="https://my.zerotier.com"
readonly ZT_SUBNET="172.22.0.0/16"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# -----------------------------------------------------------------------
# Argumente parsen
# -----------------------------------------------------------------------
SUGGESTED_IP=""
DEVICE_NAME="$(hostname)"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ip)
            SUGGESTED_IP="$2"
            shift 2
            ;;
        --name)
            DEVICE_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Unbekanntes Argument: $1  (--help für Hilfe)"
            exit 1
            ;;
    esac
done

# -----------------------------------------------------------------------
# Hilfsfunktionen
# -----------------------------------------------------------------------
step()  { echo -e "\n${CYAN}${BOLD}==> $*${NC}"; }
ok()    { echo -e "    ${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "    ${YELLOW}[WARN]${NC}  $*"; }
info()  { echo -e "    ${CYAN}[INFO]${NC}  $*"; }
error() { echo -e "    ${RED}[FEHLER]${NC} $*" >&2; }
run()   {
    if $DRY_RUN; then
        echo -e "    ${YELLOW}[DRY-RUN]${NC} $*"
    else
        "$@"
    fi
}

# -----------------------------------------------------------------------
# Root-Prüfung
# -----------------------------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
    error "Dieses Skript muss als root ausgeführt werden: sudo $0"
    exit 1
fi

echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}  ZeroTier Lab-Netzwerk Beitritt${NC}"
echo -e "${BOLD}======================================================${NC}"
echo -e "  Gerät:       ${CYAN}${DEVICE_NAME}${NC}"
echo -e "  Netzwerk-ID: ${CYAN}${ZT_NETWORK_ID}${NC}"
[[ -n "$SUGGESTED_IP" ]] && echo -e "  ZT-IP:       ${CYAN}${SUGGESTED_IP}${NC}"
$DRY_RUN && echo -e "  ${YELLOW}Modus: DRY-RUN (keine Änderungen)${NC}"
echo ""

# -----------------------------------------------------------------------
# Betriebssystem erkennen
# -----------------------------------------------------------------------
step "Betriebssystem erkennen"

OS_ID=""
PKG_MANAGER=""

if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_LIKE="${ID_LIKE:-}"
fi

if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
else
    warn "Kein bekannter Paketmanager gefunden (apt / dnf / yum)."
    warn "ZeroTier muss ggf. manuell installiert werden."
fi

info "OS: ${PRETTY_NAME:-$OS_ID}  |  Paketmanager: ${PKG_MANAGER:-keiner erkannt}"

# -----------------------------------------------------------------------
# ZeroTier installieren
# -----------------------------------------------------------------------
step "ZeroTier-One prüfen / installieren"

if command -v zerotier-cli &>/dev/null; then
    ZT_VER=$(zerotier-cli -v 2>/dev/null || echo "unbekannt")
    ok "ZeroTier bereits installiert: Version ${ZT_VER}"
else
    info "ZeroTier nicht gefunden – wird installiert..."

    if [[ "$PKG_MANAGER" == "apt" ]]; then
        # Offizielles Installationsskript (Debian/Ubuntu/Raspberry Pi OS)
        run curl -fsSL https://install.zerotier.com | bash
    elif [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
        # RHEL/Rocky/CentOS – ZeroTier stellt eigenes Repo bereit
        run curl -fsSL https://install.zerotier.com | bash
    else
        error "Automatische Installation nicht möglich."
        error "Bitte ZeroTier manuell installieren: https://www.zerotier.com/download/"
        exit 1
    fi

    ok "ZeroTier installiert"
fi

# -----------------------------------------------------------------------
# Dienst aktivieren und starten
# -----------------------------------------------------------------------
step "ZeroTier-Dienst aktivieren"

if $DRY_RUN; then
    info "DRY-RUN: systemctl enable/start zerotier-one würde ausgeführt"
else
    systemctl enable zerotier-one --quiet 2>/dev/null || true
    systemctl start  zerotier-one          2>/dev/null || true

    # Kurz warten bis der Daemon bereit ist
    for i in $(seq 1 10); do
        if zerotier-cli status &>/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
fi

ok "zerotier-one Dienst läuft"

# -----------------------------------------------------------------------
# Aktuell verbundene Netzwerke prüfen
# -----------------------------------------------------------------------
step "Verbundene Netzwerke prüfen"

if ! $DRY_RUN; then
    CURRENT_NETWORKS=$(zerotier-cli listnetworks 2>/dev/null \
        | awk 'NR>1 && $1=="200" {print $3}' || true)

    if echo "$CURRENT_NETWORKS" | grep -qF "$ZT_NETWORK_ID"; then
        ok "Gerät ist bereits Mitglied in Netzwerk ${ZT_NETWORK_ID}"
        ALREADY_JOINED=true
    else
        ALREADY_JOINED=false
        if [[ -n "$CURRENT_NETWORKS" ]]; then
            info "Bereits verbundene Netzwerke:"
            zerotier-cli listnetworks 2>/dev/null | awk 'NR>1 && $1=="200" {
                printf "    %-20s %-10s %s\n", $3, $6, $9
            }' || true
        fi
    fi
else
    ALREADY_JOINED=false
fi

# -----------------------------------------------------------------------
# Netzwerk beitreten
# -----------------------------------------------------------------------
step "Netzwerk ${ZT_NETWORK_ID} beitreten"

if ${ALREADY_JOINED:-false}; then
    info "Beitritt übersprungen (bereits Mitglied)"
else
    run zerotier-cli join "$ZT_NETWORK_ID"
    ok "Beitrittsanfrage gesendet: ${ZT_NETWORK_ID}"
fi

# -----------------------------------------------------------------------
# Status anzeigen
# -----------------------------------------------------------------------
step "Status"

if ! $DRY_RUN; then
    ZT_NODE_ID=$(zerotier-cli info 2>/dev/null | awk '{print $3}' || echo "unbekannt")
    ZT_ONLINE=$(zerotier-cli status 2>/dev/null | awk '{print $4}' || echo "?")

    echo ""
    echo -e "  ${BOLD}ZeroTier Node-ID:${NC}  ${CYAN}${ZT_NODE_ID}${NC}"
    echo -e "  ${BOLD}Online-Status:${NC}     ${ZT_ONLINE}"
    echo ""

    info "Netzwerkliste:"
    zerotier-cli listnetworks 2>/dev/null | awk 'NR>1 && $1=="200" {
        printf "    Netz: %-20s  Status: %-12s  IP: %s\n", $3, $6, $9
    }' || true
fi

# -----------------------------------------------------------------------
# Nächste Schritte
# -----------------------------------------------------------------------
echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}${GREEN}  Nächste Schritte (manuell erforderlich)${NC}"
echo -e "${BOLD}======================================================${NC}"
echo ""
echo -e "  ${YELLOW}1. Gerät in ZeroTier Central autorisieren:${NC}"
echo -e "     ${ZT_CENTRAL_URL}"
echo "     → Dein Netzwerk öffnen (${ZT_NETWORK_ID})"
echo "     → Reiter 'Members'"
if ! $DRY_RUN; then
    echo -e "     → Node ${CYAN}${ZT_NODE_ID}${NC} suchen → 'Auth' Checkbox aktivieren"
else
    echo "     → Neues Gerät suchen → 'Auth' Checkbox aktivieren"
fi
echo ""
echo -e "  ${YELLOW}2. Managed IP zuweisen:${NC}"
echo "     → In der Members-Zeile auf '+' klicken und IP eintragen"
if [[ -n "$SUGGESTED_IP" ]]; then
    echo -e "     Empfohlene IP für dieses Gerät: ${CYAN}${SUGGESTED_IP}${NC}"
fi
echo ""
echo -e "  ${YELLOW}Empfohlene IP-Zuweisung für das Lab (${ZT_SUBNET}):${NC}"
echo "     172.22.0.1  →  Raspberry Pi (Always-on-Gateway)"
echo "     172.22.0.2  →  Workstation / Laptop"
echo "     172.22.0.3  →  Proxmox Host (optional)"
echo "     172.22.0.4  →  weiteres Gerät"
echo ""
echo -e "  ${YELLOW}3. Verbindung testen (nach Autorisierung):${NC}"
echo "     sudo zerotier-cli listnetworks"
echo "     # Erwartetes Ergebnis: Status = OK, IP = 172.22.0.x"
echo ""
echo -e "  ${YELLOW}4. Verbindung zu anderen Lab-Geräten prüfen:${NC}"
echo "     ping 172.22.0.1   # Raspberry Pi"
echo "     ping 172.22.0.2   # Workstation"
echo ""
echo -e "  ${YELLOW}Nützliche ZeroTier-Befehle:${NC}"
echo "     sudo zerotier-cli status          # Online-Status"
echo "     sudo zerotier-cli listnetworks    # Netzwerke und IPs"
echo "     sudo zerotier-cli listpeers       # Verbundene Peers"
echo "     sudo zerotier-cli leave ${ZT_NETWORK_ID}  # Netzwerk verlassen"
echo ""
