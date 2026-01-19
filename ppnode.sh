#!/bin/bash
# ==================================================
# ppnode v1.0 - PPanel-node lifecycle manager
# ==================================================

set -e

# ---------- colors ----------
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
GRAY="\033[90m"
BOLD="\033[1m"
RESET="\033[0m"

# ---------- constants ----------
BASE_NAME="PPanel-node"
BASE_ETC="/etc/PPanel-node"
BASE_BIN="/usr/local/PPanel-node/ppnode"
SYSTEMD_DIR="/etc/systemd/system"
OFFICIAL_INSTALL_URL="https://raw.githubusercontent.com/perfect-panel/ppanel-node/master/scripts/install.sh"

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

status_color() {
    case "$1" in
        active)   echo -e "${GREEN}active${RESET}" ;;
        inactive) echo -e "${GRAY}inactive${RESET}" ;;
        failed)   echo -e "${RED}failed${RESET}" ;;
        *)        echo -e "${YELLOW}$1${RESET}" ;;
    esac
}

# ==================================================
# install (official installer wrapper)
# ==================================================
cmd_install() {
    require_root

    if [ -x "$BASE_BIN" ]; then
        warn "ppnode already installed, skip"
        return
    fi

    API_HOST=""
    SERVER_ID=""
    SECRET_KEY=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --api-host)   API_HOST="$2"; shift 2 ;;
            --server-id)  SERVER_ID="$2"; shift 2 ;;
            --secret-key) SECRET_KEY="$2"; shift 2 ;;
            *) err "unknown option: $1" ;;
        esac
    done

    [ -n "$API_HOST" ]   || err "--api-host is required"
    [ -n "$SERVER_ID" ]  || err "--server-id is required"
    [ -n "$SECRET_KEY" ] || err "--secret-key is required"

    TMP_DIR=$(mktemp -d)
    INSTALL_SH="$TMP_DIR/install.sh"

    ok "downloading official install script"
    wget -qO "$INSTALL_SH" "$OFFICIAL_INSTALL_URL"
    chmod +x "$INSTALL_SH"

    ok "running official installer"
    "$INSTALL_SH" \
        --api-host "$API_HOST" \
        --server-id "$SERVER_ID" \
        --secret-key "$SECRET_KEY"

    rm -rf "$TMP_DIR"
    ok "ppnode installed successfully"
}

# ==================================================
# init (environment check)
# ==================================================
cmd_init() {
    require_root

    echo -e "${BOLD}${BLUE}Checking environment${RESET}\n"

    [ -x "$BASE_BIN" ] && ok "ppnode binary found" || err "ppnode binary not found"
    [ -d "$BASE_ETC" ] && ok "base config found: $BASE_ETC" || err "base config not found"

    systemctl --version >/dev/null 2>&1 \
        && ok "systemd detected" \
        || err "systemd not found"

    ok "environment ready"
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

    [ -d "$BASE_ETC" ] || err "base config not found"
    [ ! -d "$NEW_ETC" ] || err "instance already exists"
    [ ! -f "$SERVICE_FILE" ] || err "service already exists"

    cp -a "$BASE_ETC" "$NEW_ETC"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=PPanel-node ${INSTANCE}
After=network.target

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

    systemctl daemon-reload
    ok "instance '${INSTANCE}' created"
    warn "edit config: ${NEW_ETC}/config.json"
}

# ==================================================
# remove instance
# ==================================================
cmd_remove() {
    require_root
    INSTANCE="$1"
    validate_name "$INSTANCE"

    SERVICE="$(service_name "$INSTANCE")"
    CONF="$(config_dir "$INSTANCE")"

    echo -e "${YELLOW}About to remove instance:${RESET} ${INSTANCE}"
    read -p "Type YES to continue: " C
    [ "$C" = "YES" ] || { warn "aborted"; return; }

    systemctl stop "$SERVICE" 2>/dev/null || true
    systemctl disable "$SERVICE" 2>/dev/null || true
    rm -f "${SYSTEMD_DIR}/${SERVICE}"
    rm -rf "$CONF"
    systemctl daemon-reload

    ok "instance '${INSTANCE}' removed"
}

# ==================================================
# list instances (only our services)
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

        printf "%-20s %-10b\n" "$inst" "$(status_color "$state")"
    done
}

# ==================================================
# control & status
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
        echo "3) Remove instance"
        echo "4) Start instance"
        echo "5) Stop instance"
        echo "6) Restart instance"
        echo "7) Status instance"
        echo "0) Exit"
        echo
        read -p "Select: " C

        case "$C" in
            1) cmd_list ;;
            2) read -p "Name: " N; cmd_add "$N" ;;
            3) read -p "Name: " N; cmd_remove "$N" ;;
            4) read -p "Name: " N; cmd_ctl start "$N" ;;
            5) read -p "Name: " N; cmd_ctl stop "$N" ;;
            6) read -p "Name: " N; cmd_ctl restart "$N" ;;
            7) read -p "Name: " N; cmd_status "$N" ;;
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
    install) shift; cmd_install "$@" ;;
    init)    cmd_init ;;
    add)     cmd_add "$2" ;;
    remove)  cmd_remove "$2" ;;
    list)    cmd_list ;;
    start|stop|restart) cmd_ctl "$1" "$2" ;;
    status)  cmd_status "$2" ;;
    manage|"") cmd_manage ;;
    *)
        echo "Usage:"
        echo "  ppnode install --api-host URL --server-id ID --secret-key KEY"
        echo "  ppnode init"
        echo "  ppnode add panelX"
        echo "  ppnode remove panelX"
        echo "  ppnode list"
        echo "  ppnode start|stop|restart panelX"
        echo "  ppnode status panelX"
        echo "  ppnode manage"
        ;;
esac
