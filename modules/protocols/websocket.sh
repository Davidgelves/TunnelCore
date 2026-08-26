#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/websocket.sh
#  Gestión de WebSocket SSH
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════

TC_WS_DIR="/etc/tunnelcore/websocket"
TC_WS_PY="${TC_WS_DIR}/websocket_server.py"
TC_WS_CONF="${TC_WS_DIR}/websocket.conf"
TC_WS_SERVICE="/etc/systemd/system/tunnelcore-ws.service"

tc_ws_is_running() {
    systemctl is-active --quiet tunnelcore-ws 2>/dev/null
}

tc_ws_status_mark() {
    if tc_ws_is_running; then
        printf '%bo%b' "$TC_GREEN" "$TC_NC"
    else
        printf '%bx%b' "$TC_RED" "$TC_NC"
    fi
}

tc_ws_load_conf() {
    WS_PORT="80"
    WS_STATUS="101"
    WS_TARGET="127.0.0.1:22"
    WS_BANNER=""
    if [[ -f "$TC_WS_CONF" ]]; then
        # shellcheck disable=SC1090
        . "$TC_WS_CONF"
    fi
}

tc_ws_save_conf() {
    mkdir -p "$TC_WS_DIR"
    cat > "$TC_WS_CONF" <<EOF
WS_PORT="${WS_PORT:-80}"
WS_STATUS="${WS_STATUS:-101}"
WS_TARGET="${WS_TARGET:-127.0.0.1:22}"
WS_BANNER="${WS_BANNER:-}"
EOF
}

tc_ws_start() {
    local port="$1" status_code="${2:-101}" target="${3:-127.0.0.1:22}" banner="${4:-}"
    mkdir -p "$TC_WS_DIR"
    tc_require_cmd "python3" "python3"

    local src_py
    src_py="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/websocket_server.py"
    if [[ -f "$src_py" ]]; then
        cp -f "$src_py" "$TC_WS_PY"
    fi
    chmod +x "$TC_WS_PY"

    WS_PORT="$port"
    WS_STATUS="$status_code"
    WS_TARGET="$target"
    WS_BANNER="$banner"
    tc_ws_save_conf

    cat > "$TC_WS_SERVICE" <<EOF
[Unit]
Description=TunnelCore WebSocket SSH Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${TC_WS_PY} ${port} ${status_code} ${target} "${banner}"
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable tunnelcore-ws >/dev/null 2>&1
    systemctl restart tunnelcore-ws >/dev/null 2>&1
}

tc_ws_stop() {
    systemctl stop tunnelcore-ws >/dev/null 2>&1 || true
    systemctl disable tunnelcore-ws >/dev/null 2>&1 || true
}

tc_ws_menu() {
    while true; do
        tc_clear
        tc_ws_load_conf
        tc_title "GESTIÓN WEBSOCKET SSH $(tc_ws_status_mark)"

        if ! tc_ws_is_running; then
            tc_opt "1" "ACTIVAR WEBSOCKET SSH"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01)
                    printf '%bPuerto de escucha WebSocket [Enter = 80]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r port
                    [[ -z "$port" ]] && port="80"
                    if ! tc_valid_port "$port"; then
                        tc_msg_err "Puerto no válido."
                        tc_pause
                        continue
                    fi

                    printf '%bEstado HTTP (101 Switching Protocols / 200 OK) [Enter = 101]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r st
                    [[ -z "$st" ]] && st="101"

                    printf '%bPuerto destino local (SSH) [Enter = 22]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r tgt_port
                    [[ -z "$tgt_port" ]] && tgt_port="22"

                    printf '%bMinibanner HTML (opcional):%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r banner

                    tc_ws_start "$port" "$st" "127.0.0.1:${tgt_port}" "$banner"

                    if tc_ws_is_running; then
                        tc_msg_ok "WebSocket SSH activo en puerto $port (Status $st)."
                    else
                        tc_msg_err "Error al iniciar WebSocket."
                    fi
                    tc_pause
                    ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        else
            printf '%bPUERTO:%b %b%s%b  %bSTATUS:%b %b%s%b  %bDESTINO:%b %b%s%b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "${WS_PORT:-80}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${WS_STATUS:-101}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "${WS_TARGET:-127.0.0.1:22}" "$TC_NC"
            tc_line
            tc_opt "1" "DESACTIVAR WEBSOCKET SSH"
            tc_opt "2" "RECONFIGURAR PUERTO / STATUS"
            tc_opt "3" "REINICIAR SERVICIO"
            tc_opt "4" "VER LOGS EN VIVO"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01)
                    tc_ws_stop
                    tc_msg_ok "WebSocket SSH detenido."
                    tc_pause
                    ;;
                2|02)
                    printf '%bNuevo puerto [Enter = 80]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r port
                    [[ -z "$port" ]] && port="80"
                    printf '%bEstado HTTP (101 / 200) [Enter = 101]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r st
                    [[ -z "$st" ]] && st="101"
                    tc_ws_start "$port" "$st" "${WS_TARGET:-127.0.0.1:22}" "${WS_BANNER:-}"
                    tc_msg_ok "Configuración actualizada."
                    tc_pause
                    ;;
                3|03)
                    systemctl restart tunnelcore-ws >/dev/null 2>&1
                    tc_msg_ok "WebSocket reiniciado."
                    tc_pause
                    ;;
                4|04)
                    tc_clear
                    tc_title "LOGS WEBSOCKET (Ctrl+C para salir)"
                    journalctl -u tunnelcore-ws -f --no-pager
                    ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        fi
    done
}
