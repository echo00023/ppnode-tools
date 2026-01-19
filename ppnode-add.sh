#!/bin/bash
# ==================================================
# ppnode-add : add a new ppnode instance safely
# ==================================================

set -e

# ---------- must run as root ----------
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: please run this script as root"
    exit 1
fi

BASE_NAME="PPanel-node"
BASE_ETC="/etc/PPanel-node"
BASE_BIN="/usr/local/PPanel-node/ppnode"
SYSTEMD_DIR="/etc/systemd/system"

INSTANCE="$1"

if [ -z "$INSTANCE" ]; then
    echo "Usage: ppnode-add <instance_name>"
    echo "Example: ppnode-add panel2"
    exit 1
fi

# basic name validation
if ! [[ "$INSTANCE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "ERROR: instance name contains invalid characters"
    exit 1
fi

NEW_ETC="/etc/PPanel-node-${INSTANCE}"
SERVICE_NAME="${BASE_NAME}-${INSTANCE}.service"
SERVICE_FILE="${SYSTEMD_DIR}/${SERVICE_NAME}"

# ---------- sanity checks ----------

if [ ! -d "$BASE_ETC" ]; then
    echo "ERROR: base config directory not found: $BASE_ETC"
    exit 1
fi

if [ ! -x "$BASE_BIN" ]; then
    echo "ERROR: ppnode binary not found: $BASE_BIN"
    exit 1
fi

if [ -d "$NEW_ETC" ]; then
    echo "ERROR: instance config already exists: $NEW_ETC"
    exit 1
fi

if [ -f "$SERVICE_FILE" ]; then
    echo "ERROR: systemd service already exists: $SERVICE_FILE"
    exit 1
fi

# ---------- create instance config ----------

echo "[*] Creating config directory: $NEW_ETC"
cp -a "$BASE_ETC" "$NEW_ETC"

# ---------- create systemd service ----------

echo "[*] Creating systemd service: $SERVICE_NAME"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=PPanel-node ${INSTANCE}
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root

WorkingDirectory=/usr/local/PPanel-node
ExecStart=/usr/local/PPanel-node/ppnode server -c ${NEW_ETC}/config.json

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# ---------- reload systemd ----------

echo "[*] Reloading systemd"
systemctl daemon-reload

# ---------- self install (one-line install support) ----------

if [ ! -f /usr/local/bin/ppnode-add ]; then
    echo "[*] Installing ppnode-add to /usr/local/bin"
    install -m 755 "$0" /usr/local/bin/ppnode-add
fi

# ---------- done ----------

echo
echo "✔ ppnode instance '${INSTANCE}' created successfully"
echo
echo "Next steps:"
echo "  1. Edit config (IMPORTANT):"
echo "     vim ${NEW_ETC}/config.json"
echo
echo "     - change panel address"
echo "     - change node ID"
echo "     - change listen ports"
echo
echo "  2. Start service:"
echo "     systemctl enable ${SERVICE_NAME} --now"
echo
echo "  3. Check status:"
echo "     systemctl status ${SERVICE_NAME}"
echo
