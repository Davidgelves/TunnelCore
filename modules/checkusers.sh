#!/bin/bash
# TunnelCore - modules/checkusers.sh
# Wrapper para usar el CheckUser original de ADMRufu/Rufus.

TC_RUFU_CHECKUSER_URL="https://gitlab.com/rufu99/admrufu2.0/-/raw/main/sbin/checkuser"
TC_RUFU_CHECKUSER_DIR="/root/ADMRufu/checkuser"
TC_RUFU_CHECKUSER_BIN="${TC_RUFU_CHECKUSER_DIR}/checkuser"
TC_RUFU_CHECKUSER_SERVICE="checkuser"
TC_OLD_CHECK_SERVICE="/etc/systemd/system/tunnelcore-checkuser.service"
TC_OLD_CHECK_DIR="/etc/tunnelcore/checkuser"

tc_checkuser_is_running() {
    systemctl is-active --quiet "$TC_RUFU_CHECKUSER_SERVICE" 2>/dev/null
}

tc_checkuser_status_mark() {
    if tc_checkuser_is_running; then
        printf '%bo%b' "$TC_GREEN" "$TC_NC"
    else
        printf '%bx%b' "$TC_RED" "$TC_NC"
    fi
}

tc_checkuser_stop_old_tunnelcore_api() {
    systemctl stop tunnelcore-checkuser >/dev/null 2>&1 || true
    systemctl disable tunnelcore-checkuser >/dev/null 2>&1 || true
    rm -f "$TC_OLD_CHECK_SERVICE" 2>/dev/null || true
    rm -rf "$TC_OLD_CHECK_DIR" 2>/dev/null || true
    systemctl daemon-reload >/dev/null 2>&1 || true
}

tc_checkuser_download_rufu() {
    mkdir -p "$TC_RUFU_CHECKUSER_DIR"
    tc_download "$TC_RUFU_CHECKUSER_URL" "$TC_RUFU_CHECKUSER_BIN" 3 || return 1
    chmod +x "$TC_RUFU_CHECKUSER_BIN"
}

tc_checkuser_ensure_rufu() {
    tc_checkuser_stop_old_tunnelcore_api

    if [[ "$(uname -m)" != "x86_64" && "$(uname -m)" != "amd64" ]]; then
        tc_msg_warn "El CheckUser de Rufus es binario x86_64; esta arquitectura puede no ser compatible."
        sleep 2
    fi

    if [[ ! -x "$TC_RUFU_CHECKUSER_BIN" ]]; then
        tc_clear
        tc_title "INSTALADOR CHECKUSER"
        printf '%bDescargando CheckUser original de Rufus...%b\n' "$TC_YELLOW" "$TC_NC"
        printf '%b%s%b\n' "$TC_WHITE" "$TC_RUFU_CHECKUSER_URL" "$TC_NC"
        if ! tc_checkuser_download_rufu; then
            tc_msg_err "No se pudo descargar el CheckUser de Rufus."
            tc_pause
            return 1
        fi
        tc_msg_ok "CheckUser de Rufus descargado correctamente."
        sleep 1
    fi

    return 0
}

tc_checkuser_menu() {
    if ! tc_checkuser_ensure_rufu; then
        return
    fi

    "$TC_RUFU_CHECKUSER_BIN"
}
