#!/bin/bash
# ==================================================
# ppnode v1.1 - PPanel-node multi-instance manager
# ==================================================

set -e

# ---------- colors ----------
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
BOLD="\033[1m"
RESET="\033[0m"

# ---------- constants ----------
BASE_NAME="PPanel-node"
BASE_ETC="/etc/PPanel-node"
SYSTEMD_DIR="/etc/systemd/system"

# ---------- helpers ----------
ok()   { echo -e "${GREEN}✔${RESET} $1"; }
warn() { echo -e "${YELLOW}!${RESET} $1"; }
err()  { echo -e "${RED}✘${RESET} $1"; exit 1; }

require_root() {
    [ "$(id -u)" -eq 0 ] || err "please run as root"
}

validate_name() {
    [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]] || err "invalid instance name"
}

service_name() {
    echo "${BASE_NAME}-$1.service"
}

config_dir() {
    echo "/etc/PPanel-node-$1"
}

# ==================================================
# add instance
# ==================================================
cmd_add() {
    require_root
    INSTANCE="$1"
    validate_name "$INSTANCE"

    NEW_ETC="$(config_dir "$INSTANCE")"
    SERVICE_FILE="${SYSTEMD_DIR}/$(service_name "$INSTANCE")"

    [ -d "$BASE_ETC" ] || err "base config dir not found: $BASE_ETC"
    [ ! -d "$NEW_ETC" ] || err "instance already exists"

    echo
    echo -e "${BOLD}Adding instance:${RESET} $INSTANCE"

    cp -a "$BASE_ETC" "$NEW_ETC"

    CONFIG_FILE="${NEW_ETC}/config.yml"
    [ -f "$CONFIG_FILE" ] || err "config.yml not found"

    echo
    read -p "API Host: " API_HOST
    read -p "Server ID: " SERVER_ID
    read -p "Secret Key: " SECRET_KEY

    [ -n "$API_HOST" ]   || err "ApiHost cannot be empty"
    [ -n "$SERVER_ID" ]  || err "ServerID cannot be empty"
    [ -n "$SECRET_KEY" ] || err "SecretKey cannot be empty"

    # 🔴 核心修复点：字段名 + 缩进全部正确
    sed -i -E \
      -e "s/^([[:space:]]*ApiHost:).*/\1 ${API_HOST}/" \
      -e "s/^([[:space:]]*ServerID:).*/\1 ${SERVER_ID}/" \
      -e "s/^([[:space:]]*SecretKey:).*/\1 ${SECRET_KEY}/" \
      "$CONFIG_FILE"

    ok "config.yml updated (ApiHost / ServerID / SecretKey)"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=PPanel-node ${INSTANCE}
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/usr/local/PPanel-node
ExecStart=/usr/local/PPanel-node/ppnode server -c ${NEW_ETC}/config.yml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    ok "instance '${INSTANCE}' created"
}


# ==================================================
# list instances (ONLY ours)
# ==================================================
cmd_list() {
    printf "${BOLD}%-20s %-10s${RESET}\n" "INSTANCE" "STATUS"
    printf "%-20s %-10s\n" "--------" "------"

    for svc in ${SYSTEMD_DIR}/${BASE_NAME}-*.service; do
        [ -e "$svc" ] || continue
        name=$(basename "$svc")
        inst="${name#${BASE_NAME}-}"
        inst="${inst%.service}"
        state=$(systemctl is-active "$name" 2>/dev/null || echo unknown)
        printf "%-20s %-10s\n" "$inst" "$state"
    done
}

# ==================================================
# control
# ==================================================
cmd_ctl() {
    require_root
    ACTION="$1"
    INSTANCE="$2"
    validate_name "$INSTANCE"
    systemctl "$ACTION" "$(service_name "$INSTANCE")"
}

cmd_status() {
    require_root
    INSTANCE="$1"
    validate_name "$INSTANCE"
    systemctl status "$(service_name "$INSTANCE")"
}

# ==================================================
# manage UI
# ==================================================
cmd_manage() {
    require_root
    while true; do
        clear
        echo -e "${BOLD}${BLUE}PPanel-node Manager${RESET}"
        echo "----------------------------------"
        echo "1) List instances"
        echo "2) Add instance"
        echo "3) Start instance"
        echo "4) Stop instance"
        echo "5) Restart instance"
        echo "6) Status instance"
        echo "0) Exit"
        echo
        read -p "Select: " C

        case "$C" in
            1) cmd_list ;;
            2) read -p "Name: " N; cmd_add "$N" ;;
            3) read -p "Name: " N; cmd_ctl start "$N" ;;
            4) read -p "Name: " N; cmd_ctl stop "$N" ;;
            5) read -p "Name: " N; cmd_ctl restart "$N" ;;
            6) read -p "Name: " N; cmd_status "$N" ;;
            0) exit 0 ;;
            *) warn "invalid choice" ;;
        esac

        echo
        read -p "Press Enter to continue..."
    done
}

# ==================================================
# main
# ==================================================
case "$1" in
    add)     cmd_add "$2" ;;
    list)    cmd_list ;;
    start|stop|restart) cmd_ctl "$1" "$2" ;;
    status)  cmd_status "$2" ;;
    manage|"") cmd_manage ;;
    *)
        echo "Usage:"
        echo "  ppnode add panelX"
        echo "  ppnode list"
        echo "  ppnode start|stop|restart panelX"
        echo "  ppnode status panelX"
        echo "  ppnode manage"
        ;;
esac
