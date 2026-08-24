#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/proxy.sh
#  Gestión de Proxy HTTP / SOCKS (Payload / WebSocket / Auto)
#  Soporta Proxy 1 (Principal) y Proxy 2 (Secundario) simultáneos
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_PROXY_DIR="/etc/tunnelcore/proxy"
TC_PROXY_PY="${TC_PROXY_DIR}/proxy_server.py"

TC_P1_CONF="${TC_PROXY_DIR}/proxy1.conf"
TC_P1_SERVICE="/etc/systemd/system/tunnelcore-proxy.service"

TC_P2_CONF="${TC_PROXY_DIR}/proxy2.conf"
TC_P2_SERVICE="/etc/systemd/system/tunnelcore-proxy2.service"

tc_p1_is_running() { systemctl is-active --quiet tunnelcore-proxy 2>/dev/null; }
tc_p2_is_running() { systemctl is-active --quiet tunnelcore-proxy2 2>/dev/null; }

tc_proxy_status_mark() {
    local running=0
    tc_p1_is_running && (( running++ ))
    tc_p2_is_running && (( running++ ))

    if (( running > 0 )); then
        printf '%b[%s ACTIVO(S)]%b' "$TC_GREEN" "$running" "$TC_NC"
    elif [[ -f "$TC_P1_CONF" || -f "$TC_P2_CONF" ]]; then
        printf '%b[OFF]%b' "$TC_RED" "$TC_NC"
    else
        printf '%b[NO INSTALADO]%b' "$TC_YELLOW" "$TC_NC"
    fi
}

tc_proxy_load_conf() {
    local id="${1:-1}"
    local conf_file="${TC_PROXY_DIR}/proxy${id}.conf"
    P_PORT="80"
    P_STATUS="AUTO"
    P_TARGET="127.0.0.1:22"
    P_BANNER=""

    if [[ -f "$conf_file" ]]; then
        # shellcheck disable=SC1090
        . "$conf_file"
    elif [[ "$id" == "2" ]]; then
        P_PORT="8080"
        P_STATUS="AUTO"
    fi
}

tc_proxy_save_conf() {
    local id="${1:-1}"
    local conf_file="${TC_PROXY_DIR}/proxy${id}.conf"
    mkdir -p "$TC_PROXY_DIR"
    cat > "$conf_file" <<EOF
P_PORT="${P_PORT:-80}"
P_STATUS="${P_STATUS:-AUTO}"
P_TARGET="${P_TARGET:-127.0.0.1:22}"
P_BANNER="${P_BANNER:-}"
EOF
}

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

tc_proxy_start_instance() {
    local id="${1:-1}" port="$2" status_code="${3:-AUTO}" target="${4:-127.0.0.1:22}" banner="${5:-}"
    local svc_file="/etc/systemd/system/tunnelcore-proxy${id}.service"
    [[ "$id" == "1" ]] && svc_file="/etc/systemd/system/tunnelcore-proxy.service"

    mkdir -p "$TC_PROXY_DIR"
    tc_require_cmd "python3" "python3"

    local src_py
    src_py="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/proxy_server.py"
    if [[ -f "$src_py" ]]; then
        cp -f "$src_py" "$TC_PROXY_PY"
    fi
    chmod +x "$TC_PROXY_PY"

    P_PORT="$port"
    P_STATUS="$status_code"
    P_TARGET="$target"
    P_BANNER="$banner"
    tc_proxy_save_conf "$id"

    cat > "$svc_file" <<EOF
[Unit]
Description=TunnelCore HTTP/SOCKS Proxy Instance ${id}
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
    local svc_name="tunnelcore-proxy"
    [[ "$id" == "2" ]] && svc_name="tunnelcore-proxy2"

    systemctl enable "$svc_name" >/dev/null 2>&1
    systemctl restart "$svc_name" >/dev/null 2>&1
}

tc_proxy_stop_instance() {
    local id="${1:-1}"
    local svc_name="tunnelcore-proxy"
    [[ "$id" == "2" ]] && svc_name="tunnelcore-proxy2"
    systemctl stop "$svc_name" >/dev/null 2>&1 || true
    systemctl disable "$svc_name" >/dev/null 2>&1 || true
}

tc_proxy_manage_instance() {
    local id="${1:-1}"
    local title="PROXY HTTP 1 (PRINCIPAL)"
    [[ "$id" == "2" ]] && title="PROXY HTTP 2 (SECUNDARIO)"

    while true; do
        tc_clear
        tc_proxy_load_conf "$id"
        local is_run=0
        [[ "$id" == "1" ]] && tc_p1_is_running && is_run=1
        [[ "$id" == "2" ]] && tc_p2_is_running && is_run=1

        local st_mark
        (( is_run == 1 )) && st_mark="${TC_GREEN}[ON]${TC_NC}" || st_mark="${TC_RED}[OFF]${TC_NC}"

        tc_title "${title} ${st_mark}"

        if (( is_run == 0 )); then
            tc_opt "1" "ACTIVAR ${title}"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01)
                    local def_p="80"
                    [[ "$id" == "2" ]] && def_p="8080"

                    printf '%bPuerto de escucha del Proxy [Enter = %s]:%b ' "$TC_DARK_GREEN" "$def_p" "$TC_NC"
                    read -r port
                    [[ -z "$port" ]] && port="$def_p"
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

                    printf '\n%bMinibanner / Respuesta de Encabezado (Opcional - Enter para omitir):%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r banner

                    tc_proxy_start_instance "$id" "$port" "$st" "$TC_SELECTED_TARGET" "$banner"
                    tc_msg_ok "${title} activado en puerto $port (Status $st) redirigiendo a $TC_SELECTED_TARGET."
                    tc_pause
                    ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        else
            printf '%bPUERTO:%b %b%s%b  %bSTATUS:%b %b%s%b  %bDESTINO:%b %b%s%b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "${P_PORT:-80}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${P_STATUS:-AUTO}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "${P_TARGET:-127.0.0.1:22}" "$TC_NC"
            tc_line
            tc_opt "1" "DESACTIVAR ESTE PROXY"
            tc_opt "2" "REDIRIGIR DESTINO (SSH / DROPBEAR)"
            tc_opt "3" "CAMBIAR PUERTO DE ESCUCHA"
            tc_opt "4" "CAMBIAR ESTADO HTTP (AUTO, 200, 101, etc.)"
            tc_opt "5" "CAMBIAR MINIBANNER"
            tc_opt "6" "REINICIAR SERVICIO"
            tc_opt "7" "VER LOGS EN VIVO"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01)
                    tc_proxy_stop_instance "$id"
                    tc_msg_ok "${title} detenido."
                    tc_pause
                    ;;
                2|02)
                    if tc_proxy_ask_target "${P_PORT:-80}"; then
                        tc_proxy_start_instance "$id" "${P_PORT:-80}" "${P_STATUS:-AUTO}" "$TC_SELECTED_TARGET" "${P_BANNER:-}"
                        tc_msg_ok "Destino actualizado a $TC_SELECTED_TARGET."
                        tc_pause
                    fi
                    ;;
                3|03)
                    printf '%bNuevo puerto de escucha [Enter = %s]:%b ' "$TC_DARK_GREEN" "${P_PORT:-80}" "$TC_NC"
                    read -r new_p
                    if [[ -n "$new_p" ]] && tc_valid_port "$new_p"; then
                        tc_proxy_start_instance "$id" "$new_p" "${P_STATUS:-AUTO}" "${P_TARGET:-127.0.0.1:22}" "${P_BANNER:-}"
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
                        tc_proxy_start_instance "$id" "${P_PORT:-80}" "$new_st" "${P_TARGET:-127.0.0.1:22}" "${P_BANNER:-}"
                        tc_msg_ok "Estado HTTP actualizado a $new_st."
                        tc_pause
                    fi
                    ;;
                5|05)
                    printf '%bMinibanner actual:%b %s\n' "$TC_DARK_GREEN" "$TC_NC" "${P_BANNER:-Ninguno}"
                    printf '%bIngrese nuevo minibanner (Enter para borrar):%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r new_ban
                    tc_proxy_start_instance "$id" "${P_PORT:-80}" "${P_STATUS:-AUTO}" "${P_TARGET:-127.0.0.1:22}" "$new_ban"
                    tc_msg_ok "Minibanner actualizado."
                    tc_pause
                    ;;
                6|06)
                    local svc_name="tunnelcore-proxy"
                    [[ "$id" == "2" ]] && svc_name="tunnelcore-proxy2"
                    systemctl restart "$svc_name" >/dev/null 2>&1
                    tc_msg_ok "Servicio reiniciado."
                    tc_pause
                    ;;
                7|07)
                    tc_clear
                    local svc_name="tunnelcore-proxy"
                    [[ "$id" == "2" ]] && svc_name="tunnelcore-proxy2"
                    tc_title "LOGS PROXY ${id} (Ctrl+C para salir)"
                    journalctl -u "$svc_name" -f --no-pager
                    ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        fi
    done
}

tc_proxy_menu() {
    while true; do
        tc_clear
        local p1_st="${TC_RED}[OFF]${TC_NC}" p2_st="${TC_RED}[OFF]${TC_NC}"
        tc_p1_is_running && p1_st="${TC_GREEN}[ON]${TC_NC}"
        tc_p2_is_running && p2_st="${TC_GREEN}[ON]${TC_NC}"

        tc_title "PROXY HTTP / SOCKS $(tc_proxy_status_mark)"

        tc_opt "1" "GESTIONAR PROXY 1 (PRINCIPAL)" "  $p1_st"
        tc_opt "2" "GESTIONAR PROXY 2 (SECUNDARIO)" "  $p2_st"
        tc_line
        tc_opt "0" "$(_t 'back')"
        tc_line
        tc_prompt
        read -r main_p_opt

        case "$main_p_opt" in
            1|01) tc_proxy_manage_instance "1" ;;
            2|02) tc_proxy_manage_instance "2" ;;
            0|00) break ;;
            *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
        esac
    done
}
