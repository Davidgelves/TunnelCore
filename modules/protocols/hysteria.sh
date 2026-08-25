#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/hysteria.sh
#  Gestión de UDP-Hysteria v1 1:1 con NoxuraSSH
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_HYST_BIN="/usr/local/bin/hysteria1"
TC_HYST_DIR="/etc/tunnelcore/hysteria"
TC_HYST_CONF="${TC_HYST_DIR}/config.json"
TC_HYST_ENV="${TC_HYST_DIR}/tunnelcore.env"
TC_HYST_CERT="${TC_HYST_DIR}/server.crt"
TC_HYST_KEY="${TC_HYST_DIR}/server.key"
TC_HYST_IPTABLES="${TC_HYST_DIR}/iptables.sh"
TC_HYST_SERVICE="/etc/systemd/system/hysteria-server.service"

tc_hyst_is_installed() {
    [[ -x "$TC_HYST_BIN" && -f "$TC_HYST_CONF" ]]
}

tc_hyst_is_running() {
    systemctl is-active --quiet hysteria-server 2>/dev/null
}

tc_hyst_status_mark() {
    if tc_hyst_is_running; then
        printf '%b[ON]%b' "$TC_GREEN" "$TC_NC"
    elif [[ -f "$TC_HYST_CONF" ]]; then
        printf '%b[OFF]%b' "$TC_RED" "$TC_NC"
    else
        printf '%b[NO INSTALADO]%b' "$TC_YELLOW" "$TC_NC"
    fi
}

tc_hyst_load_env() {
    HYST_PORT="36712"
    HYST_RULES="none"
    HYST_OBFS=""
    if [[ -f "$TC_HYST_ENV" ]]; then
        # shellcheck disable=SC1090
        . "$TC_HYST_ENV"
    fi
}

tc_hyst_client_ranges() {
    local value="${1// /}"
    echo "${value//:/-}"
}

tc_hyst_valid_rule_ranges() {
    local value="${1// /}" item first last
    [[ -n "$value" ]] || return 1
    [[ "$value" = "none" ]] && return 0
    IFS=',' read -ra _items <<<"$value"
    for item in "${_items[@]}"; do
        [[ "$item" =~ ^[0-9]+(:[0-9]+)?$ ]] || return 1
        first="${item%%:*}"
        last="${item##*:}"
        [[ "$item" != *:* ]] && last="$first"
        (( first >= 1 && first <= 65535 && last >= 1 && last <= 65535 && first <= last )) || return 1
    done
}

tc_hyst_json_quote() {
    printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

tc_hyst_shell_quote() {
    printf '%q' "$1"
}

tc_hyst_build_auth_list() {
    local db="/etc/tunnelcore/users.db" pass_dir="/etc/tunnelcore/passwords" user pass found=0 sep=""
    
    # Migración de compatibilidad con NoxuraSSH si existen usuarios previos
    if [[ ! -s "$db" && -f "/root/usuarios.db" ]]; then
        db="/root/usuarios.db"
        pass_dir="/etc/SSHPlus/senha"
    fi

    if [[ -f "$db" ]]; then
        while IFS='|' read -r u _ _ _ || [[ -n "$u" ]]; do
            user="$(echo "$u" | tr -d ' ')"
            [[ -z "$user" ]] && continue
            if [[ -f "${pass_dir}/${user}" ]]; then
                pass="$(cat "${pass_dir}/${user}" 2>/dev/null)"
            elif [[ -f "/etc/tunnelcore/passwords/${user}" ]]; then
                pass="$(cat "/etc/tunnelcore/passwords/${user}" 2>/dev/null)"
            else
                continue
            fi
            [[ -z "$pass" ]] && continue
            printf '%s      %s\n' "$sep" "$(tc_hyst_json_quote "${user}:${pass}")"
            sep=","
            found=1
        done < "$db"
    fi

    [[ "$found" = "1" ]]
}

tc_hyst_install_binary() {
    if [[ -x "$TC_HYST_BIN" ]]; then
        return 0
    fi
    tc_msg_ok "Descargando Hysteria v1..."
    local asset url
    local arch
    arch="$(tc_detect_arch)"
    case "$arch" in
        amd64) asset="hysteria-linux-amd64" ;;
        arm64) asset="hysteria-linux-arm64" ;;
        *) tc_msg_err "Arquitectura no compatible para Hysteria v1."; return 1 ;;
    esac

    url="https://github.com/apernet/hysteria/releases/download/v1.3.5/${asset}"
    local tmp="/tmp/hysteria.$$"

    if curl -fL --connect-timeout 5 --max-time 30 -o "$tmp" "$url" 2>/dev/null && [[ -s "$tmp" ]]; then
        chmod +x "$tmp"
        mv -f "$tmp" "$TC_HYST_BIN"
    elif wget -q --timeout=15 -O "$tmp" "$url" 2>/dev/null && [[ -s "$tmp" ]]; then
        chmod +x "$tmp"
        mv -f "$tmp" "$TC_HYST_BIN"
    else
        tc_msg_err "No se pudo descargar Hysteria v1."
        return 1
    fi
    chmod +x "$TC_HYST_BIN"
    [[ -x "$TC_HYST_BIN" ]]
}

tc_hyst_write_iptables_helper() {
    mkdir -p "$TC_HYST_DIR"
    cat > "$TC_HYST_IPTABLES" <<'EOF'
#!/bin/bash
ACTION="$1"
ENV_FILE="/etc/tunnelcore/hysteria/tunnelcore.env"
CHAIN="TC_HYSTERIA"

[[ -f "$ENV_FILE" ]] && . "$ENV_FILE"

clear_rules() {
    while iptables -t nat -C PREROUTING -p udp -j "$CHAIN" >/dev/null 2>&1; do
        iptables -t nat -D PREROUTING -p udp -j "$CHAIN" >/dev/null 2>&1 || break
    done
    iptables -t nat -F "$CHAIN" >/dev/null 2>&1 || true
    iptables -t nat -X "$CHAIN" >/dev/null 2>&1 || true
    iptables -D INPUT -p udp --dport "${HYST_PORT:-36712}" -j ACCEPT >/dev/null 2>&1 || true
}

apply_rules() {
    clear_rules
    iptables -I INPUT 1 -p udp --dport "${HYST_PORT:-36712}" -j ACCEPT >/dev/null 2>&1 || true
    [[ -z "$HYST_RULES" || "$HYST_RULES" = "none" || "$HYST_RULES" = "0" ]] && return 0
    iptables -t nat -N "$CHAIN" >/dev/null 2>&1 || true
    iptables -t nat -I PREROUTING 1 -p udp -j "$CHAIN" >/dev/null 2>&1 || true
    local clean="${HYST_RULES// /}" item
    IFS=',' read -ra items <<<"$clean"
    for item in "${items[@]}"; do
        [[ -z "$item" || "$item" = "53" || "$item" = "5300" ]] && continue
        iptables -t nat -A "$CHAIN" -p udp --dport "$item" -j REDIRECT --to-ports "$HYST_PORT" >/dev/null 2>&1 || true
    done
}

case "$ACTION" in
    apply) apply_rules ;;
    clear) clear_rules ;;
esac
EOF
    chmod +x "$TC_HYST_IPTABLES"
}

tc_hyst_write_service() {
    tc_hyst_write_iptables_helper
    cat > "$TC_HYST_SERVICE" <<EOF
[Unit]
Description=TunnelCore Hysteria v1 Server
After=network.target

[Service]
Type=simple
Environment=HYSTERIA_LOG_LEVEL=info
ExecStart=${TC_HYST_BIN} -c ${TC_HYST_CONF} server
ExecStartPre=${TC_HYST_IPTABLES} apply
ExecStopPost=${TC_HYST_IPTABLES} clear
WorkingDirectory=${TC_HYST_DIR}
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable hysteria-server >/dev/null 2>&1
}

tc_hyst_write_config() {
    local port="$1" rules="$2" obfs="$3" auth_block
    auth_block="$(tc_hyst_build_auth_list)" || return 2
    mkdir -p "$TC_HYST_DIR"

    if [[ ! -f "$TC_HYST_CERT" || ! -f "$TC_HYST_KEY" ]]; then
        openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
            -keyout "$TC_HYST_KEY" -out "$TC_HYST_CERT" -subj "/CN=tunnelcore-hysteria" >/dev/null 2>&1
    fi

    cat > "$TC_HYST_CONF" <<EOF
{
  "listen": ":${port}",
  "cert": "${TC_HYST_CERT}",
  "key": "${TC_HYST_KEY}",
  "obfs": $(tc_hyst_json_quote "$obfs"),
  "auth": {
    "mode": "passwords",
    "config": [
${auth_block}
    ]
  }
}
EOF
    cat > "$TC_HYST_ENV" <<EOF
HYST_PORT=$(tc_hyst_shell_quote "$port")
HYST_RULES=$(tc_hyst_shell_quote "$rules")
HYST_OBFS=$(tc_hyst_shell_quote "$obfs")
EOF
    chmod 600 "$TC_HYST_CONF" "$TC_HYST_ENV" "$TC_HYST_KEY" 2>/dev/null || true
}

tc_hyst_sync_users() {
    [[ -f "$TC_HYST_ENV" ]] || return 0
    tc_hyst_load_env
    if ! tc_hyst_build_auth_list >/dev/null 2>&1; then
        systemctl stop hysteria-server >/dev/null 2>&1 || true
        return 0
    fi
    tc_hyst_write_config "${HYST_PORT:-36712}" "${HYST_RULES:-none}" "${HYST_OBFS:-$(tc_rand_string 18)}" || return 0
    tc_hyst_install_binary >/dev/null 2>&1 && tc_hyst_write_service
    systemctl restart hysteria-server >/dev/null 2>&1 || true
}

tc_hyst_show_info() {
    tc_hyst_load_env
    local ip
    ip="$(tc_public_ip)"
    local client_port="${HYST_PORT:-36712}"
    [[ -n "${HYST_RULES:-}" && "$HYST_RULES" != "none" ]] && client_port="$(tc_hyst_client_ranges "$HYST_RULES")"

    printf '%bPuerto principal:%b %s\n' "$TC_GREEN" "$TC_NC" "${HYST_PORT:-N/A}"
    printf '%bRangos iptables:%b %s\n' "$TC_GREEN" "$TC_NC" "${HYST_RULES:-none}"
    printf '%bOBFS:%b %s\n' "$TC_GREEN" "$TC_NC" "${HYST_OBFS:-N/A}"
    printf '%bServidor:%b %s:%s\n' "$TC_GREEN" "$TC_NC" "${ip:-IP_VPS}" "$client_port"
    printf '%bAuth Hysteria v1:%b use usuario:contraseña SSH\n' "$TC_GREEN" "$TC_NC"
    printf '%bTLS cliente:%b insecure/allowInsecure = true\n' "$TC_GREEN" "$TC_NC"
    printf '%b%s%b\n' "$TC_YELLOW" "TLS usa certificado propio; en el cliente active insecure/allowInsecure." "$TC_NC"
}

tc_hyst_show_summary() {
    tc_hyst_load_env
    local redirect
    redirect="$(tc_hyst_client_ranges "${HYST_RULES:-N/A}")"
    [[ "$redirect" = "none" ]] && redirect="Deshabilitado"

    tc_line
    printf '%b                       UDP-HYSTERIA v1%b\n' "$TC_CYAN" "$TC_NC"
    tc_line
    printf '%bVERSION:%b %bHYSTERIA v1%b\n' "$TC_WHITE" "$TC_NC" "$TC_PALE_GOLD" "$TC_NC"
    printf '%bPORT:%b %b%s%b\n' "$TC_WHITE" "$TC_NC" "$TC_PALE_GOLD" "${HYST_PORT:-36712}" "$TC_NC"
    printf '%bREDIRECT:%b %b%s > %s%b\n' "$TC_WHITE" "$TC_NC" "$TC_PALE_GOLD" "${redirect}" "${HYST_PORT:-36712}" "$TC_NC"
    printf '%bOBFS:%b %b%s%b\n' "$TC_WHITE" "$TC_NC" "$TC_PALE_GOLD" "${HYST_OBFS:-N/A}" "$TC_NC"
    tc_line
}

tc_hyst_configure() {
    tc_clear
    tc_title "INSTALAR HYSTERIA v1 UDP"

    local port rules obfs hop_resp
    if ! tc_hyst_build_auth_list >/dev/null 2>&1; then
        tc_msg_err "No hay usuarios SSH con contraseña guardada."
        printf '%bCree usuarios desde el menú de usuarios y vuelva a instalar Hysteria v1.%b\n' "$TC_WHITE" "$TC_NC"
        tc_pause
        return
    fi

    printf '%bPuerto principal Hysteria v1 [36712]:%b ' "$TC_GREEN" "$TC_NC"
    read -r port
    [[ -z "$port" ]] && port="36712"
    if ! tc_valid_port "$port"; then
        tc_msg_err "Puerto inválido."
        sleep 2
        return
    fi

    printf '%b¿Habilitar Port Hopping (Rangos UDP)? [s/N]:%b ' "$TC_GREEN" "$TC_NC"
    read -r hop_resp
    if [[ "$hop_resp" =~ ^[sS]$ ]]; then
        printf '%bRangos iptables UDP [20000:50000]:%b ' "$TC_GREEN" "$TC_NC"
        read -r rules
        [[ -z "$rules" ]] && rules="20000:50000"
        if ! tc_hyst_valid_rule_ranges "$rules"; then
            tc_msg_err "Rangos inválidos. Ejemplo: 20000:50000"
            sleep 2
            return
        fi
    else
        rules="none"
    fi

    printf '%bOBFS Hysteria v1 [Enter = aleatorio]:%b ' "$TC_GREEN" "$TC_NC"
    read -r obfs
    [[ -z "$obfs" ]] && obfs="$(tc_rand_string 18)"

    tc_hyst_install_binary || { tc_pause; return; }
    tc_hyst_write_config "$port" "$rules" "$obfs" || {
        tc_msg_err "No se pudo sincronizar usuarios SSH para Hysteria v1."
        tc_pause
        return
    }

    tc_hyst_write_service
    systemctl restart hysteria-server >/dev/null 2>&1

    tc_line
    tc_msg_ok "Hysteria v1 instalado/configurado correctamente."
    tc_hyst_show_info
    tc_pause
}

tc_hyst_change_obfs() {
    tc_hyst_load_env
    printf '%bNuevo OBFS Hysteria v1:%b ' "$TC_GREEN" "$TC_NC"
    read -r new_obfs
    [[ -z "$new_obfs" ]] && return
    tc_hyst_write_config "${HYST_PORT:-36712}" "${HYST_RULES:-none}" "$new_obfs"
    systemctl restart hysteria-server >/dev/null 2>&1
    tc_msg_ok "OBFS actualizado."
    tc_pause
}

tc_hyst_change_range() {
    while true; do
        tc_clear
        tc_title "RANGOS IPTABLES HYSTERIA v1"
        tc_hyst_load_env
        printf '%bPuerto principal:%b %s\n' "$TC_GREEN" "$TC_NC" "${HYST_PORT:-36712}"
        printf '%bReglas actuales:%b %s\n' "$TC_DARK_GREEN" "$TC_NC" "${HYST_RULES:-none}"
        tc_line
        tc_opt "1" "MODIFICAR RANGO IPTABLE (Desde:Hasta)"
        tc_opt "2" "PONER REGLA DE RANGOS IPTABLES MANUAL"
        tc_opt "3" "DESHABILITAR RANGOS (Solo puerto principal)"
        tc_line
        tc_opt "0" "$(_t 'back')"
        tc_line
        tc_prompt
        read -r range_opt

        case "$range_opt" in
            1)
                local from_p to_p new_rules
                printf '%bDesde puerto [1]:%b ' "$TC_GREEN" "$TC_NC"
                read -r from_p
                [[ -z "$from_p" ]] && from_p="1"
                printf '%bHasta puerto [65535]:%b ' "$TC_GREEN" "$TC_NC"
                read -r to_p
                [[ -z "$to_p" ]] && to_p="65535"
                new_rules="${from_p}:${to_p}"
                if ! tc_hyst_valid_rule_ranges "$new_rules"; then
                    tc_msg_err "Rango inválido."
                    sleep 2
                    continue
                fi
                tc_hyst_write_config "${HYST_PORT:-36712}" "$new_rules" "${HYST_OBFS:-$(tc_rand_string 18)}"
                systemctl restart hysteria-server >/dev/null 2>&1
                tc_msg_ok "Rango actualizado a $new_rules."
                tc_pause
                ;;
            2)
                printf '%bReglas de rangos UDP [ej: 20000:50000]:%b ' "$TC_GREEN" "$TC_NC"
                read -r new_rules
                [[ -z "$new_rules" ]] && new_rules="20000:50000"
                if ! tc_hyst_valid_rule_ranges "$new_rules"; then
                    tc_msg_err "Reglas inválidas."
                    sleep 2
                    continue
                fi
                tc_hyst_write_config "${HYST_PORT:-36712}" "$new_rules" "${HYST_OBFS:-$(tc_rand_string 18)}"
                systemctl restart hysteria-server >/dev/null 2>&1
                tc_msg_ok "Reglas actualizadas a $new_rules."
                tc_pause
                ;;
            3)
                tc_hyst_write_config "${HYST_PORT:-36712}" "none" "${HYST_OBFS:-$(tc_rand_string 18)}"
                systemctl restart hysteria-server >/dev/null 2>&1
                tc_msg_ok "Rangos deshabilitados. Solo puerto principal activo."
                tc_pause
                ;;
            0|00) return ;;
            *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
        esac
    done
}

tc_hyst_toggle_service() {
    if tc_hyst_is_running; then
        systemctl stop hysteria-server >/dev/null 2>&1
        tc_msg_ok "Hysteria v1 detenido."
    else
        systemctl start hysteria-server >/dev/null 2>&1
        tc_msg_ok "Hysteria v1 iniciado."
    fi
    tc_pause
}

tc_hyst_service_status() {
    tc_clear
    tc_title "ESTADO HYSTERIA v1"
    systemctl status hysteria-server --no-pager -l 2>/dev/null || tc_msg_err "Servicio no instalado."
    tc_pause
}

tc_hyst_uninstall() {
    tc_clear
    tc_title "DESINSTALAR HYSTERIA v1"

    if ! tc_confirm "¿Desea desinstalar Hysteria v1?"; then
        return
    fi

    systemctl stop hysteria-server >/dev/null 2>&1 || true
    systemctl disable hysteria-server >/dev/null 2>&1 || true
    [[ -x "$TC_HYST_IPTABLES" ]] && "$TC_HYST_IPTABLES" clear >/dev/null 2>&1 || true

    rm -f "$TC_HYST_SERVICE" "$TC_HYST_BIN"
    rm -rf "$TC_HYST_DIR"
    systemctl daemon-reload >/dev/null 2>&1 || true
    tc_msg_ok "Hysteria v1 desinstalado por completo."
    tc_pause
}

tc_hyst_show_logs() {
    tc_clear
    tc_title "LOG HYSTERIA v1"
    systemctl status hysteria-server --no-pager -l 2>/dev/null | tail -n 20
    echo ""
    journalctl -u hysteria-server -n 30 --no-pager 2>/dev/null
    tc_pause
}

tc_hyst_follow_logs() {
    tc_clear
    tc_title "LOG EN VIVO HYSTERIA v1 (Ctrl+C para salir)"
    printf '%bIntente conectar desde el cliente ahora. Use CTRL+C para salir.%b\n' "$TC_WHITE" "$TC_NC"
    tc_line
    journalctl -u hysteria-server -f --no-pager
}

tc_hyst_menu() {
    while true; do
        tc_clear
        if [[ ! -f "$TC_HYST_CONF" ]]; then
            tc_line
            printf '%b                       UDP-HYSTERIA v1%b\n' "$TC_CYAN" "$TC_NC"
            tc_line
            tc_opt "1" "INSTALAR HYSTERIA v1"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_hyst_configure ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        else
            tc_hyst_show_summary
            tc_opt "1" "RECONFIGURAR UDP-HYSTERIA v1"
            tc_opt "2" "MODIFICAR OBFS"
            tc_line
            tc_opt "3" "MODIFICAR RANGOS IPTABLE"
            tc_opt "4" "ESTADO DEL SERVICIO"
            tc_opt "5" "REINICIAR SERVICIO"
            tc_opt "6" "INICIAR/PARAR SERVICIO" "  $(tc_hyst_status_mark)"
            tc_line
            tc_opt "7" "LOG UDP-HYSTERIA v1"
            tc_opt "8" "LOG UDP-HYSTERIA v1 EN TIEMPO REAL"
            tc_line
            printf "%b  %b  %b\n" "${TC_NEON}[0]${TC_NC} ${TC_WHITE}>${TC_NC} $(_t 'back')" "${TC_NEON}[9]${TC_NC} ${TC_WHITE}>${TC_NC} REINSTALAR" "${TC_NEON}[10]${TC_NC} ${TC_WHITE}>${TC_NC} DESINSTALAR"
            tc_line
            tc_prompt
            read -r opt

            case "$opt" in
                1|01) tc_hyst_configure ;;
                2|02) tc_hyst_change_obfs ;;
                3|03) tc_hyst_change_range ;;
                4|04) tc_hyst_service_status ;;
                5|05) systemctl restart hysteria-server && tc_msg_ok "Servicio reiniciado." && tc_pause ;;
                6|06) tc_hyst_toggle_service ;;
                7|07) tc_hyst_show_logs ;;
                8|08) tc_hyst_follow_logs ;;
                9|09) rm -f "$TC_HYST_BIN"; tc_hyst_configure ;;
                10) tc_hyst_uninstall ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        fi
    done
}

case "${1:-}" in
    --sync) tc_hyst_sync_users ;;
esac
