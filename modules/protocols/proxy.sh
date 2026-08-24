#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/proxy.sh
#  Gestión de Proxy SOCKS / HTTP Custom
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
    if [[ -f "$TC_PROXY_CONF" ]]; then
        # shellcheck disable=SC1090
        . "$TC_PROXY_CONF"
    fi
}

tc_proxy_save_conf() {
    mkdir -p "$TC_PROXY_DIR"
    cat > "$TC_PROXY_CONF" <<EOF
PROXY_PORT="${PROXY_PORT:-80}"
EOF
}

tc_proxy_start() {
    local port="$1"
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
    tc_proxy_save_conf

    cat > "$TC_PROXY_SERVICE" <<EOF
[Unit]
Description=TunnelCore SOCKS Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${TC_PROXY_PY} ${port}
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
        tc_title "GESTIÓN PROXY SOCKS $(tc_proxy_status_mark)"

        if ! tc_proxy_is_running; then
            tc_opt "1" "ACTIVAR PROXY SOCKS"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01)
                    printf '%bPuerto de escucha SOCKS [Enter = 80]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r port
                    [[ -z "$port" ]] && port="80"
                    if ! tc_valid_port "$port"; then
                        tc_msg_err "Puerto no válido."
                        tc_pause
                        continue
                    fi
                    if tc_port_in_use "$port"; then
                        tc_msg_warn "El puerto $port ya está en uso."
                        if ! tc_confirm "¿Continuar de todos modos?"; then
                            continue
                        fi
                    fi
                    tc_proxy_start "$port"
                    if tc_proxy_is_running; then
                        tc_msg_ok "Proxy SOCKS activado en puerto $port."
                    else
                        tc_msg_err "Error al iniciar Proxy SOCKS."
                    fi
                    tc_pause
                    ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        else
            printf '%bPUERTO:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "${PROXY_PORT:-80}" "$TC_NC"
            tc_line
            tc_opt "1" "DESACTIVAR PROXY SOCKS"
            tc_opt "2" "CAMBIAR PUERTO"
            tc_opt "3" "REINICIAR SERVICIO"
            tc_opt "4" "VER LOGS EN VIVO"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01)
                    tc_proxy_stop
                    tc_msg_ok "Proxy SOCKS detenido."
                    tc_pause
                    ;;
                2|02)
                    printf '%bNuevo puerto de escucha [Enter = 80]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r new_port
                    [[ -z "$new_port" ]] && new_port="80"
                    if tc_valid_port "$new_port"; then
                        tc_proxy_start "$new_port"
                        tc_msg_ok "Puerto actualizado a $new_port."
                    else
                        tc_msg_err "Puerto no válido."
                    fi
                    tc_pause
                    ;;
                3|03)
                    systemctl restart tunnelcore-proxy >/dev/null 2>&1
                    tc_msg_ok "Proxy SOCKS reiniciado."
                    tc_pause
                    ;;
                4|04)
                    tc_clear
                    tc_title "LOGS PROXY SOCKS (Ctrl+C para salir)"
                    journalctl -u tunnelcore-proxy -f --no-pager
                    ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        fi
    done
}

