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

# ── Submenú para seleccionar a qué puerto redirigir el Proxy ───
tc_proxy_select_target() {
    local default_dropbear_port="90"
    if [[ -f /etc/default/dropbear ]]; then
        default_dropbear_port="$(grep -oE '^DROPBEAR_PORT=[0-9]+' /etc/default/dropbear 2>/dev/null | cut -d'=' -f2 || echo "90")"
    fi

    tc_clear
    tc_title "REDIRIGIR PUERTO HTTP PROXY"
    printf '%b%-10s %-20s %s%b\n' "$TC_WHITE" "OPCIÓN" "PUERTO" "DESTINO" "$TC_NC"
    tc_line
    tc_opt "1" "22    -----------> SSH (OpenSSH)"
    tc_opt "2" "${default_dropbear_port}    -----------> Dropbear"
    tc_opt "3" "PUERTO PERSONALIZADO"
    tc_line
    tc_opt "0" "$(_t 'back')"
    tc_line
    tc_prompt
    read -r t_opt

    case "$t_opt" in
        1) echo "127.0.0.1:22" ;;
        2) echo "127.0.0.1:${default_dropbear_port}" ;;
        3)
            printf '%bIngrese puerto destino local [1-65535]:%b ' "$TC_DARK_GREEN" "$TC_NC" >&2
            read -r cust_p
            if tc_valid_port "$cust_p"; then
                echo "127.0.0.1:${cust_p}"
            else
                echo "127.0.0.1:22"
            fi
            ;;
        0|*) echo "CANCEL" ;;
    esac
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
                    printf '%bPuerto de escucha del Proxy [Enter = 80]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r port
                    [[ -z "$port" ]] && port="80"
                    if ! tc_valid_port "$port"; then
                        tc_msg_err "Puerto no válido."
                        tc_pause
                        continue
                    fi

                    local target_chosen
                    target_chosen="$(tc_proxy_select_target)"
                    [[ "$target_chosen" == "CANCEL" ]] && continue

                    printf '%bEstado HTTP (200 OK, 101 WS, 204 No Content) [Enter = 200]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r st
                    [[ -z "$st" ]] && st="200"

                    printf '%bMinibanner HTML / Respuesta de Encabezado (opcional):%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r banner

                    tc_proxy_start "$port" "$st" "$target_chosen" "$banner"
                    if tc_proxy_is_running; then
                        tc_msg_ok "Proxy HTTP/SOCKS activado en puerto $port redirigiendo a $target_chosen."
                    else
                        tc_msg_err "Error al iniciar Proxy HTTP/SOCKS."
                    fi
                    tc_pause
                    ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        else
            printf '%bPUERTO:%b %b%s%b  %bSTATUS:%b %b%s%b  %bDESTINO:%b %b%s%b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "${PROXY_PORT:-80}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${PROXY_STATUS:-200}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "${PROXY_TARGET:-127.0.0.1:22}" "$TC_NC"
            tc_line
            tc_opt "1" "DESACTIVAR PROXY"
            tc_opt "2" "CAMBIAR DESTINO DE REDIRECCIÓN (SSH / DROPBEAR)"
            tc_opt "3" "CAMBIAR PUERTO DE ESCUCHA"
            tc_opt "4" "CAMBIAR ESTADO HTTP (200, 101, etc.)"
            tc_opt "5" "PERSONALIZAR MINIBANNER / ENCABEZADO"
            tc_opt "6" "REINICIAR SERVICIO"
            tc_opt "7" "VER LOGS EN VIVO"
            tc_line
            tc_opt "0" "$(_t 'back')"
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
                    local new_target
                    new_target="$(tc_proxy_select_target)"
                    if [[ "$new_target" != "CANCEL" ]]; then
                        tc_proxy_start "${PROXY_PORT:-80}" "${PROXY_STATUS:-200}" "$new_target" "${PROXY_BANNER:-}"
                        tc_msg_ok "Destino actualizado a $new_target."
                    fi
                    tc_pause
                    ;;
                3|03)
                    printf '%bNuevo puerto de escucha [Enter = %s]:%b ' "$TC_DARK_GREEN" "${PROXY_PORT:-80}" "$TC_NC"
                    read -r new_p
                    if [[ -n "$new_p" ]] && tc_valid_port "$new_p"; then
                        tc_proxy_start "$new_p" "${PROXY_STATUS:-200}" "${PROXY_TARGET:-127.0.0.1:22}" "${PROXY_BANNER:-}"
                        tc_msg_ok "Puerto actualizado a $new_p."
                    else
                        tc_msg_err "Puerto no válido."
                    fi
                    tc_pause
                    ;;
                4|04)
                    tc_clear
                    tc_title "SELECCIONAR ESTADO HTTP"
                    tc_opt "1" "200 OK (HTTP Custom / Injector / Payload estándar)"
                    tc_opt "2" "101 Switching Protocols (WebSocket SSH)"
                    tc_opt "3" "204 No Content"
                    tc_opt "4" "Código personalizado (ej: 301, 302, etc.)"
                    tc_line
                    tc_opt "0" "$(_t 'cancel')"
                    tc_line
                    tc_prompt
                    read -r st_opt
                    local new_st=""
                    case "$st_opt" in
                        1) new_st="200" ;;
                        2) new_st="101" ;;
                        3) new_st="204" ;;
                        4)
                            printf '%bIngrese código HTTP (ej: 302):%b ' "$TC_DARK_GREEN" "$TC_NC"
                            read -r cust_st
                            [[ -n "$cust_st" ]] && new_st="$cust_st"
                            ;;
                        0|*) continue ;;
                    esac
                    if [[ -n "$new_st" ]]; then
                        tc_proxy_start "${PROXY_PORT:-80}" "$new_st" "${PROXY_TARGET:-127.0.0.1:22}" "${PROXY_BANNER:-}"
                        tc_msg_ok "Estado HTTP actualizado a $new_st."
                        tc_pause
                    fi
                    ;;
                5|05)
                    printf '%bMinibanner actual:%b %s\n' "$TC_DARK_GREEN" "$TC_NC" "${PROXY_BANNER:-Ninguno}"
                    printf '%bIngrese nuevo minibanner (Enter para borrar):%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r new_ban
                    tc_proxy_start "${PROXY_PORT:-80}" "${PROXY_STATUS:-200}" "${PROXY_TARGET:-127.0.0.1:22}" "$new_ban"
                    tc_msg_ok "Minibanner actualizado."
                    tc_pause
                    ;;
                6|06)
                    systemctl restart tunnelcore-proxy >/dev/null 2>&1
                    tc_msg_ok "Proxy reiniciado."
                    tc_pause
                    ;;
                7|07)
                    tc_clear
                    tc_title "LOGS PROXY (Ctrl+C para salir)"
                    journalctl -u tunnelcore-proxy -f --no-pager
                    ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        fi
    done
}
