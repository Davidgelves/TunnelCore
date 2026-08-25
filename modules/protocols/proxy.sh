#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/proxy.sh
#  Gestión Directa y Unificada de Proxy HTTP / SOCKS (Modo AUTO)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_PROXY_DIR="/etc/tunnelcore/proxy"
TC_PROXY_PY="${TC_PROXY_DIR}/proxy_server.py"
TC_PROXY_CONF="${TC_PROXY_DIR}/proxy.conf"
TC_PROXY_SERVICE="/etc/systemd/system/tunnelcore-proxy.service"
TC_PROXY2_SERVICE="/etc/systemd/system/tunnelcore-proxy2.service"

tc_proxy_is_running() {
    systemctl is-active --quiet tunnelcore-proxy 2>/dev/null
}

tc_proxy2_is_running() {
    systemctl is-active --quiet tunnelcore-proxy2 2>/dev/null
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
    PROXY_STATUS="AUTO"
    PROXY_TARGET="127.0.0.1:22"
    PROXY_BANNER=""
    PROXY_PORT2=""

    # Migrar configuraciones anteriores si existen
    if [[ -f "${TC_PROXY_DIR}/proxy1.conf" && ! -f "$TC_PROXY_CONF" ]]; then
        cp -f "${TC_PROXY_DIR}/proxy1.conf" "$TC_PROXY_CONF"
    fi

    if [[ -f "$TC_PROXY_CONF" ]]; then
        # shellcheck disable=SC1090
        . "$TC_PROXY_CONF"
    fi
}

tc_proxy_save_conf() {
    mkdir -p "$TC_PROXY_DIR"
    cat > "$TC_PROXY_CONF" <<EOF
PROXY_PORT="${PROXY_PORT:-80}"
PROXY_STATUS="${PROXY_STATUS:-AUTO}"
PROXY_TARGET="${PROXY_TARGET:-127.0.0.1:22}"
PROXY_BANNER="${PROXY_BANNER:-}"
PROXY_PORT2="${PROXY_PORT2:-}"
EOF
}

# ── Selector de Redirección de Tráfico ─────────────────────────
TC_SELECTED_TARGET="127.0.0.1:22"

tc_proxy_ask_target() {
    local listen_p="${1:-80}"
    local dropbear_p="90"

    if [[ -f /etc/default/dropbear ]]; then
        dropbear_p="$(grep -oE '^DROPBEAR_PORT=[0-9]+' /etc/default/dropbear 2>/dev/null | cut -d'=' -f2 || echo "90")"
    fi

    while true; do
        tc_clear
        tc_title "CONFIGURAR PROXY (REDIRECCION)"
        printf '%bPUERTO PROXY (escucha):%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$listen_p" "$TC_NC"
        tc_line
        printf '%b       ¿A QUÉ PUERTO REDIRIGIR EL TRÁFICO?%b\n' "$TC_YELLOW" "$TC_NC"
        tc_line
        printf '%b[1]%b %b> SSH (OpenSSH) ....................%b %b22%b\n' "$TC_NEON" "$TC_NC" "$TC_WHITE" "$TC_NC" "$TC_GREEN" "$TC_NC"
        printf '%b[2]%b %b> Dropbear SSH .....................%b %b%s%b\n' "$TC_NEON" "$TC_NC" "$TC_WHITE" "$TC_NC" "$TC_GREEN" "$dropbear_p" "$TC_NC"
        printf '%b[3]%b %b> INGRESAR PUERTO MANUALMENTE%b\n' "$TC_NEON" "$TC_NC" "$TC_WHITE" "$TC_NC"
        tc_line
        tc_opt "0" "$(_t 'cancel')"
        tc_line

        tc_prompt
        read -r ch

        case "$ch" in
            1) TC_SELECTED_TARGET="127.0.0.1:22"; return 0 ;;
            2) TC_SELECTED_TARGET="127.0.0.1:${dropbear_p}"; return 0 ;;
            3)
                printf '%bIngrese puerto destino local [1-65535]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                read -r manual_p
                if tc_valid_port "$manual_p"; then
                    TC_SELECTED_TARGET="127.0.0.1:${manual_p}"
                    return 0
                else
                    tc_msg_err "Puerto inválido."
                    sleep 1
                    continue
                fi
                ;;
            0) return 1 ;;
            *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
        esac
    done
}

tc_proxy_start() {
    local port="$1" status_code="${2:-AUTO}" target="${3:-127.0.0.1:22}" banner="${4:-}" port2="${5:-}"
    mkdir -p "$TC_PROXY_DIR"
    tc_require_cmd "python3" "python3"

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
    PROXY_PORT2="$port2"
    tc_proxy_save_conf

    # Servicio Principal
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

    # Servicio Secundario (Opcional si se configuró puerto 2)
    if [[ -n "$port2" && "$port2" != "0" ]]; then
        cat > "$TC_PROXY2_SERVICE" <<EOF
[Unit]
Description=TunnelCore HTTP/SOCKS Proxy Secondary Port
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${TC_PROXY_PY} ${port2} ${status_code} ${target} "${banner}"
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable tunnelcore-proxy2 >/dev/null 2>&1
        systemctl restart tunnelcore-proxy2 >/dev/null 2>&1
    else
        systemctl stop tunnelcore-proxy2 >/dev/null 2>&1 || true
        systemctl disable tunnelcore-proxy2 >/dev/null 2>&1 || true
    fi
}

tc_proxy_stop() {
    systemctl stop tunnelcore-proxy tunnelcore-proxy2 >/dev/null 2>&1 || true
    systemctl disable tunnelcore-proxy tunnelcore-proxy2 >/dev/null 2>&1 || true
}

tc_proxy_menu() {
    while true; do
        tc_clear
        tc_proxy_load_conf
        tc_title "PROXY HTTP / SOCKS $(tc_proxy_status_mark)"

        if ! tc_proxy_is_running; then
            tc_opt "1" "ACTIVAR PROXY HTTP / SOCKS"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01)
                    printf '%bPuerto de escucha principal [Enter = 80]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r port
                    [[ -z "$port" ]] && port="80"
                    if ! tc_valid_port "$port"; then
                        tc_msg_err "Puerto no válido."
                        tc_pause
                        continue
                    fi

                    if ! tc_proxy_ask_target "$port"; then
                        continue
                    fi

                    tc_clear
                    tc_title "SELECCIONAR ESTADO HTTP"
                    tc_opt "1" "AUTO / NEUTRO (200 OK + 101 WebSocket Dinámico) [Recomendado]"
                    tc_opt "2" "200 OK FIJO (Solo Payloads / Inyectores directos)"
                    tc_opt "3" "101 WEBSOCKET FIJO (Solo WebSocket / CDN)"
                    tc_opt "4" "204 NO CONTENT"
                    tc_opt "5" "Código personalizado (ej: 302, etc.)"
                    tc_line
                    tc_prompt
                    read -r st_opt
                    local st="AUTO"
                    case "$st_opt" in
                        2) st="200" ;;
                        3) st="101" ;;
                        4) st="204" ;;
                        5)
                            printf '%bCódigo HTTP:%b ' "$TC_DARK_GREEN" "$TC_NC"
                            read -r cust_st
                            [[ -n "$cust_st" ]] && st="$cust_st"
                            ;;
                        *) st="AUTO" ;;
                    esac

                    printf '\n%bMinibanner / Encabezado personalizado (Enter para omitir):%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r banner

                    tc_proxy_start "$port" "$st" "$TC_SELECTED_TARGET" "$banner" ""
                    if tc_proxy_is_running; then
                        tc_msg_ok "Proxy HTTP/SOCKS activado en puerto $port (Status $st) redirigiendo a $TC_SELECTED_TARGET."
                    else
                        tc_msg_err "Error al iniciar Proxy HTTP/SOCKS."
                    fi
                    tc_pause
                    ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        else
            local extra_port_str=""
            [[ -n "${PROXY_PORT2:-}" ]] && extra_port_str=", ${PROXY_PORT2}"

            printf '%bPUERTOS:%b %b%s%s%b  %bSTATUS:%b %b%s%b  %bDESTINO:%b %b%s%b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "${PROXY_PORT:-80}" "$extra_port_str" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${PROXY_STATUS:-AUTO}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "${PROXY_TARGET:-127.0.0.1:22}" "$TC_NC"
            tc_line
            tc_opt "1" "DESACTIVAR PROXY"
            tc_opt "2" "REDIRIGIR DESTINO (SSH / DROPBEAR)"
            tc_opt "3" "CAMBIAR PUERTO PRINCIPAL"
            tc_opt "4" "CAMBIAR ESTADO HTTP (AUTO, 200, 101, etc.)"
            tc_opt "5" "AGREGAR / QUITAR PUERTO SECUNDARIO"
            tc_opt "6" "CAMBIAR MINIBANNER"
            tc_opt "7" "REINICIAR SERVICIO"
            tc_opt "8" "VER LOGS EN VIVO"
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
                    if tc_proxy_ask_target "${PROXY_PORT:-80}"; then
                        tc_proxy_start "${PROXY_PORT:-80}" "${PROXY_STATUS:-AUTO}" "$TC_SELECTED_TARGET" "${PROXY_BANNER:-}" "${PROXY_PORT2:-}"
                        tc_msg_ok "Destino actualizado a $TC_SELECTED_TARGET."
                        tc_pause
                    fi
                    ;;
                3|03)
                    printf '%bNuevo puerto principal [Enter = %s]:%b ' "$TC_DARK_GREEN" "${PROXY_PORT:-80}" "$TC_NC"
                    read -r new_p
                    if [[ -n "$new_p" ]] && tc_valid_port "$new_p"; then
                        tc_proxy_start "$new_p" "${PROXY_STATUS:-AUTO}" "${PROXY_TARGET:-127.0.0.1:22}" "${PROXY_BANNER:-}" "${PROXY_PORT2:-}"
                        tc_msg_ok "Puerto actualizado a $new_p."
                    else
                        tc_msg_err "Puerto no válido."
                    fi
                    tc_pause
                    ;;
                4|04)
                    tc_clear
                    tc_title "SELECCIONAR ESTADO HTTP"
                    tc_opt "1" "AUTO / NEUTRO (200 OK + 101 WebSocket Dinámico) [Recomendado]"
                    tc_opt "2" "200 OK FIJO (Solo Payloads / Inyectores)"
                    tc_opt "3" "101 WEBSOCKET FIJO (Solo WebSocket / CDN)"
                    tc_opt "4" "204 NO CONTENT"
                    tc_opt "5" "Código personalizado (ej: 302, etc.)"
                    tc_line
                    tc_opt "0" "$(_t 'cancel')"
                    tc_line
                    tc_prompt
                    read -r st_opt
                    local new_st=""
                    case "$st_opt" in
                        1) new_st="AUTO" ;;
                        2) new_st="200" ;;
                        3) new_st="101" ;;
                        4) new_st="204" ;;
                        5)
                            printf '%bIngrese código HTTP (ej: 302):%b ' "$TC_DARK_GREEN" "$TC_NC"
                            read -r cust_st
                            [[ -n "$cust_st" ]] && new_st="$cust_st"
                            ;;
                        0|*) continue ;;
                    esac
                    if [[ -n "$new_st" ]]; then
                        tc_proxy_start "${PROXY_PORT:-80}" "$new_st" "${PROXY_TARGET:-127.0.0.1:22}" "${PROXY_BANNER:-}" "${PROXY_PORT2:-}"
                        tc_msg_ok "Estado HTTP actualizado a $new_st."
                        tc_pause
                    fi
                    ;;
                5|05)
                    printf '%bPuerto secundario actual:%b %s\n' "$TC_DARK_GREEN" "$TC_NC" "${PROXY_PORT2:-Ninguno}"
                    printf '%bIngrese puerto secundario (o Enter para quitar):%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r new_p2
                    if [[ -z "$new_p2" ]]; then
                        tc_proxy_start "${PROXY_PORT:-80}" "${PROXY_STATUS:-AUTO}" "${PROXY_TARGET:-127.0.0.1:22}" "${PROXY_BANNER:-}" ""
                        tc_msg_ok "Puerto secundario removido."
                    elif tc_valid_port "$new_p2"; then
                        tc_proxy_start "${PROXY_PORT:-80}" "${PROXY_STATUS:-AUTO}" "${PROXY_TARGET:-127.0.0.1:22}" "${PROXY_BANNER:-}" "$new_p2"
                        tc_msg_ok "Puerto secundario $new_p2 agregado y activo."
                    else
                        tc_msg_err "Puerto no válido."
                    fi
                    tc_pause
                    ;;
                6|06)
                    printf '%bMinibanner actual:%b %s\n' "$TC_DARK_GREEN" "$TC_NC" "${PROXY_BANNER:-Ninguno}"
                    printf '%bIngrese nuevo minibanner (Enter para borrar):%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r new_ban
                    tc_proxy_start "${PROXY_PORT:-80}" "${PROXY_STATUS:-AUTO}" "${PROXY_TARGET:-127.0.0.1:22}" "$new_ban" "${PROXY_PORT2:-}"
                    tc_msg_ok "Minibanner actualizado."
                    tc_pause
                    ;;
                7|07)
                    systemctl restart tunnelcore-proxy >/dev/null 2>&1
                    [[ -n "${PROXY_PORT2:-}" ]] && systemctl restart tunnelcore-proxy2 >/dev/null 2>&1 || true
                    tc_msg_ok "Proxy reiniciado."
                    tc_pause
                    ;;
                8|08)
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
