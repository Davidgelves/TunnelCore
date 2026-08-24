#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/proxy.sh
#  Gestión de Proxy HTTP / SOCKS (Payload / Injector)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_PROXY_DIR="/etc/tunnelcore/proxy"
TC_PROXY_PY="${TC_PROXY_DIR}/proxy_server.py"
TC_PROXY_CONF="${TC_PROXY_DIR}/proxy.conf"
TC_PROXY_SERVICE="/etc/systemd/system/tunnelcore-proxy.service"

tc_proxy_is_running() {
    systemctl is-active --quiet tunnelcore-proxy 2>/dev/null
}

tc_proxy_status_mark() {
    if tc_proxy_is_running; then
        printf '%b[ON]%b' "$TC_GREEN" "$TC_NC"
    elif [[ -f "$TC_PROXY_CONF" ]]; then
        printf '%b[OFF]%b' "$TC_RED" "$TC_NC"
    else
        printf '%b[NO INSTALADO]%b' "$TC_YELLOW" "$TC_NC"
    fi
}

tc_proxy_load_conf() {
    PROXY_PORT="80"
    PROXY_STATUS="200"
    PROXY_TARGET="127.0.0.1:22"
    PROXY_BANNER=""
    if [[ -f "$TC_PROXY_CONF" ]]; then
        # shellcheck disable=SC1090
        . "$TC_PROXY_CONF"
    fi
}

tc_proxy_save_conf() {
    mkdir -p "$TC_PROXY_DIR"
    cat > "$TC_PROXY_CONF" <<EOF
PROXY_PORT="${PROXY_PORT:-80}"
PROXY_STATUS="${PROXY_STATUS:-200}"
PROXY_TARGET="${PROXY_TARGET:-127.0.0.1:22}"
PROXY_BANNER="${PROXY_BANNER:-}"
EOF
}

tc_proxy_start() {
    local port="$1" status_code="${2:-200}" target="${3:-127.0.0.1:22}" banner="${4:-}"
    mkdir -p "$TC_PROXY_DIR"
    tc_require_cmd "python3" "python3"

    # Copiar script python al directorio del sistema
    local src_py
    src_py="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/proxy_server.py"
    if [[ -f "$src_py" ]]; then
        cp -f "$src_py" "$TC_PROXY_PY"
    fi
    chmod +x "$TC_PROXY_PY"

    PROXY_PORT="$port"
    PROXY_STATUS="$status_code"
    PROXY_TARGET="$target"
    PROXY_BANNER="$banner"
    tc_proxy_save_conf

    cat > "$TC_PROXY_SERVICE" <<EOF
[Unit]
Description=TunnelCore HTTP/SOCKS Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${TC_PROXY_PY} ${port} ${status_code} ${target} "${banner}"
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable tunnelcore-proxy >/dev/null 2>&1
    systemctl restart tunnelcore-proxy >/dev/null 2>&1
}

tc_proxy_stop() {
    systemctl stop tunnelcore-proxy >/dev/null 2>&1 || true
    systemctl disable tunnelcore-proxy >/dev/null 2>&1 || true
}

tc_proxy_menu() {
    while true; do
        tc_clear
        tc_proxy_load_conf
        tc_title "PROXY HTTP / SOCKS (PAYLOAD) $(tc_proxy_status_mark)"

        if ! tc_proxy_is_running; then
            tc_opt "1" "ACTIVAR PROXY HTTP / SOCKS"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01)
                    printf '%bPuerto de escucha [Enter = 80]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r port
                    [[ -z "$port" ]] && port="80"
                    if ! tc_valid_port "$port"; then
                        tc_msg_err "Puerto no válido."
                        tc_pause
                        continue
                    fi

                    printf '%bEstado HTTP (200 OK, 101 WS, 204 No Content) [Enter = 200]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r st
                    [[ -z "$st" ]] && st="200"

                    printf '%bPuerto destino local (SSH=22, Dropbear=110) [Enter = 22]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r tgt_port
                    [[ -z "$tgt_port" ]] && tgt_port="22"

                    printf '%bMinibanner HTML / Respuesta personalizada (opcional):%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r banner

                    tc_proxy_start "$port" "$st" "127.0.0.1:${tgt_port}" "$banner"
                    if tc_proxy_is_running; then
                        tc_msg_ok "Proxy HTTP/SOCKS activado en puerto $port."
                    else
                        tc_msg_err "Error al iniciar Proxy HTTP/SOCKS."
                    fi
                    tc_pause
                    ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        else
            printf '%bPUERTO:%b %b%s%b  %bSTATUS:%b %b%s%b  %bDESTINO:%b %b%s%b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "${PROXY_PORT:-80}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${PROXY_STATUS:-200}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "${PROXY_TARGET:-127.0.0.1:22}" "$TC_NC"
            tc_line
            tc_opt "1" "DESACTIVAR PROXY"
            tc_opt "2" "RECONFIGURAR PUERTO / STATUS / DESTINO"
            tc_opt "3" "PERSONALIZAR MINIBANNER / RESPUESTA"
            tc_opt "4" "REINICIAR SERVICIO"
            tc_opt "5" "VER LOGS EN VIVO"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01)
                    tc_proxy_stop
                    tc_msg_ok "Proxy detenido."
                    tc_pause
                    ;;
                2|02)
                    printf '%bNuevo puerto [Enter = %s]:%b ' "$TC_DARK_GREEN" "${PROXY_PORT:-80}" "$TC_NC"
                    read -r new_port
                    [[ -z "$new_port" ]] && new_port="${PROXY_PORT:-80}"
                    printf '%bNuevo estado HTTP (200 / 101) [Enter = %s]:%b ' "$TC_DARK_GREEN" "${PROXY_STATUS:-200}" "$TC_NC"
                    read -r new_st
                    [[ -z "$new_st" ]] && new_st="${PROXY_STATUS:-200}"
                    printf '%bNuevo destino local [Enter = %s]:%b ' "$TC_DARK_GREEN" "${PROXY_TARGET:-127.0.0.1:22}" "$TC_NC"
                    read -r new_tgt
                    [[ -z "$new_tgt" ]] && new_tgt="${PROXY_TARGET:-127.0.0.1:22}"
                    tc_proxy_start "$new_port" "$new_st" "$new_tgt" "${PROXY_BANNER:-}"
                    tc_msg_ok "Proxy reconfigurado y reiniciado."
                    tc_pause
                    ;;
                3|03)
                    printf '%bMinibanner actual:%b %s\n' "$TC_DARK_GREEN" "$TC_NC" "${PROXY_BANNER:-Ninguno}"
                    printf '%bIngrese nuevo minibanner (Enter para borrar):%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r new_ban
                    tc_proxy_start "${PROXY_PORT:-80}" "${PROXY_STATUS:-200}" "${PROXY_TARGET:-127.0.0.1:22}" "$new_ban"
                    tc_msg_ok "Minibanner actualizado."
                    tc_pause
                    ;;
                4|04)
                    systemctl restart tunnelcore-proxy >/dev/null 2>&1
                    tc_msg_ok "Proxy reiniciado."
                    tc_pause
                    ;;
                5|05)
                    tc_clear
                    tc_title "LOGS PROXY (Ctrl+C para salir)"
                    journalctl -u tunnelcore-proxy -f --no-pager
                    ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        fi
    done
}
