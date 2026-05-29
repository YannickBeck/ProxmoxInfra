#!/usr/bin/env python3
"""
Wake-on-LAN REST API
====================
A simple Flask REST API that sends WOL magic packets on demand.

Endpoints:
  GET  /status         - Health check, returns {"status": "ok"}
  POST /wake           - Send WOL to the Proxmox host MAC (from config file)
  POST /wake           - With JSON body {"mac": "xx:xx:xx:xx:xx:xx"} for custom MAC

Authentication:
  All POST requests require the X-API-Key header.
  The key is read from the API_KEY environment variable (set via /etc/wol/wol-api.env).

Configuration:
  API_KEY         - Required. Secret key for request authentication.
  WOL_CONFIG      - Optional. Path to config file with MAC= line.
                    Default: /etc/wol/proxmox.conf

Usage:
  export API_KEY="your_secret_key"
  python3 wol-api.py

  Or via systemd (wol-api.service) which sets the env vars from /etc/wol/wol-api.env.

Default listening address: 0.0.0.0:8080
"""

import os
import re
import subprocess
import logging
from functools import wraps
from flask import Flask, request, jsonify

# -----------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------
CONFIG_FILE = os.environ.get("WOL_CONFIG", "/etc/wol/proxmox.conf")
API_KEY = os.environ.get("API_KEY", "")
LISTEN_HOST = os.environ.get("LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8080"))

# -----------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

# -----------------------------------------------------------------------
# Flask app
# -----------------------------------------------------------------------
app = Flask(__name__)

# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------
MAC_PATTERN = re.compile(r'^([0-9a-fA-F]{2}[:\-]){5}[0-9a-fA-F]{2}$')


def is_valid_mac(mac: str) -> bool:
    """Return True if mac is a valid colon- or dash-separated MAC address."""
    return bool(MAC_PATTERN.match(mac))


def read_mac_from_config() -> str | None:
    """Read MAC address from the config file.

    Returns the MAC address string or None if not found.
    """
    if not os.path.isfile(CONFIG_FILE):
        logger.warning("Config file not found: %s", CONFIG_FILE)
        return None
    try:
        with open(CONFIG_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("MAC="):
                    mac = line.split("=", 1)[1].strip()
                    if is_valid_mac(mac):
                        return mac
                    else:
                        logger.warning("Invalid MAC in config file: %s", mac)
                        return None
    except OSError as e:
        logger.error("Failed to read config file: %s", e)
    return None


def send_wol(mac: str) -> tuple[bool, str]:
    """Send a WOL magic packet to the given MAC address.

    Tries wakeonlan first, falls back to etherwake.
    Returns (success: bool, message: str).
    """
    mac_normalised = mac.lower().replace("-", ":")

    # Try wakeonlan (preferred — no root required)
    try:
        result = subprocess.run(
            ["wakeonlan", mac_normalised],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            logger.info("WOL packet sent via wakeonlan to %s", mac_normalised)
            return True, f"Magic packet sent to {mac_normalised} via wakeonlan"
        else:
            logger.warning("wakeonlan failed: %s", result.stderr.strip())
    except FileNotFoundError:
        logger.debug("wakeonlan not found, trying etherwake...")
    except subprocess.TimeoutExpired:
        logger.warning("wakeonlan timed out")

    # Fall back to etherwake (requires root/sudo)
    try:
        result = subprocess.run(
            ["sudo", "etherwake", mac_normalised],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            logger.info("WOL packet sent via etherwake to %s", mac_normalised)
            return True, f"Magic packet sent to {mac_normalised} via etherwake"
        else:
            msg = f"etherwake failed: {result.stderr.strip()}"
            logger.error(msg)
            return False, msg
    except FileNotFoundError:
        msg = "Neither wakeonlan nor etherwake is installed. Run: sudo apt install wakeonlan"
        logger.error(msg)
        return False, msg
    except subprocess.TimeoutExpired:
        msg = "etherwake timed out"
        logger.error(msg)
        return False, msg


# -----------------------------------------------------------------------
# Authentication decorator
# -----------------------------------------------------------------------
def require_api_key(f):
    """Decorator that requires a valid X-API-Key header."""
    @wraps(f)
    def decorated(*args, **kwargs):
        if not API_KEY:
            # No API key configured — warn and allow (development mode)
            logger.warning("API_KEY is not set. Running without authentication!")
            return f(*args, **kwargs)

        provided_key = request.headers.get("X-API-Key", "")
        if provided_key != API_KEY:
            logger.warning(
                "Unauthorized request from %s — invalid API key",
                request.remote_addr
            )
            return jsonify({"error": "Unauthorized"}), 401
        return f(*args, **kwargs)
    return decorated


# -----------------------------------------------------------------------
# Routes
# -----------------------------------------------------------------------
@app.route("/status", methods=["GET"])
def status():
    """Health check endpoint."""
    config_mac = read_mac_from_config()
    return jsonify({
        "status": "ok",
        "config_file": CONFIG_FILE,
        "proxmox_mac_configured": config_mac is not None,
        "proxmox_mac": config_mac if config_mac else "not configured"
    })


@app.route("/wake", methods=["POST"])
@require_api_key
def wake():
    """Send WOL magic packet.

    Uses MAC from config file by default.
    Optionally accepts JSON body: {"mac": "xx:xx:xx:xx:xx:xx"}
    """
    # Try to get MAC from request body
    mac = None
    if request.is_json:
        body = request.get_json(silent=True) or {}
        mac = body.get("mac")

    # Validate custom MAC if provided
    if mac:
        if not is_valid_mac(mac):
            return jsonify({
                "success": False,
                "error": f"Invalid MAC address format: {mac}"
            }), 400
        logger.info("Wake request for custom MAC: %s from %s", mac, request.remote_addr)
    else:
        # Fall back to configured MAC
        mac = read_mac_from_config()
        if not mac:
            return jsonify({
                "success": False,
                "error": (
                    f"No MAC address configured in {CONFIG_FILE} "
                    "and none provided in request body"
                )
            }), 500
        logger.info(
            "Wake request for Proxmox host MAC: %s from %s",
            mac, request.remote_addr
        )

    success, message = send_wol(mac)
    status_code = 200 if success else 500

    return jsonify({
        "success": success,
        "mac": mac,
        "message": message
    }), status_code


# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------
if __name__ == "__main__":
    if not API_KEY:
        logger.warning(
            "WARNING: API_KEY environment variable is not set. "
            "The API is running without authentication!"
        )
    else:
        logger.info("WOL API starting with authentication enabled")

    config_mac = read_mac_from_config()
    if config_mac:
        logger.info("Proxmox host MAC loaded from config: %s", config_mac)
    else:
        logger.warning(
            "No MAC address found in %s. "
            "WOL will require MAC in request body or config file.",
            CONFIG_FILE
        )

    logger.info("Starting WOL API on %s:%d", LISTEN_HOST, LISTEN_PORT)
    app.run(host=LISTEN_HOST, port=LISTEN_PORT, debug=False)
