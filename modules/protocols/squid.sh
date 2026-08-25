#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/squid.sh
#  Gestión de Squid Proxy
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════

TC_SQUID_CONF="/etc/squid/squid.conf"
[[ -d "/etc/squid3" ]] && TC_SQUID_CONF="/etc/squid3/squid.conf"

tc_squid_is_installed() {
    command -v squid >/dev/null 2>&1 || command -v squid3 >/dev/null 2>&1
}

tc_squid_is_running() {
    systemctl is-active --quiet squid 2>/dev/null || systemctl is-active --quiet squid3 2>/dev/null || pgrep -x squid >/dev/null 2>&1
}

tc_squid_status_mark() {
    if tc_squid_is_running; then
        printf '%b[ON]%b' "$TC_GREEN" "$TC_NC"
    elif tc_squid_is_installed; then
        printf '%b[OFF]%b' "$TC_RED" "$TC_NC"
    else
        printf '%b[NO INSTALADO]%b' "$TC_YELLOW" "$TC_NC"
    fi
}

tc_squid_install() {
    tc_clear
    tc_title "INSTALAR SQUID PROXY"

    local port vps_ip
    vps_ip="$(tc_public_ip)"

    printf '%bPuerto(s) para Squid [ej: 80 8080 8799] (Enter = 8080):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r port
    [[ -z "$port" ]] && port="8080"

    tc_apt_install squid

    local conf_dir="/etc/squid"
    [[ -d "/etc/squid3" ]] && conf_dir="/etc/squid3"
    mkdir -p "$conf_dir"
    local conf_file="${conf_dir}/squid.conf"
    local pay_file="${conf_dir}/payload.txt"

    cat > "$pay_file" <<EOF
.whatsapp.net/
.facebook.net/
.twitter.com/
.speedtest.net/
EOF

    cat > "$conf_file" <<EOF
acl url1 dstdomain -i 127.0.0.1
acl url2 dstdomain -i localhost
acl url3 dstdomain -i ${vps_ip}
acl payload url_regex -i "${pay_file}"
acl all src 0.0.0.0/0

http_access allow url1
http_access allow url2
http_access allow url3
http_access allow payload
http_access deny all

EOF

    for p in $port; do
        if tc_valid_port "$p"; then
            echo "http_port ${p}" >> "$conf_file"
        fi
    done

    cat >> "$conf_file" <<EOF
visible_hostname TunnelCore
via off
forwarded_for off
pipeline_prefetch off
EOF

    systemctl enable squid >/dev/null 2>&1 || systemctl enable squid3 >/dev/null 2>&1 || true
    systemctl restart squid >/dev/null 2>&1 || systemctl restart squid3 >/dev/null 2>&1 || true

    if tc_squid_is_running; then
        tc_msg_ok "Squid Proxy instalado y activo en puerto(s): $port"
    else
        tc_msg_err "Error al iniciar Squid Proxy."
    fi
    tc_pause
}

tc_squid_stop() {
    systemctl stop squid >/dev/null 2>&1 || systemctl stop squid3 >/dev/null 2>&1 || true
    systemctl disable squid >/dev/null 2>&1 || systemctl disable squid3 >/dev/null 2>&1 || true
    tc_msg_ok "Squid Proxy detenido."
    tc_pause
}

tc_squid_uninstall() {
    if tc_confirm "¿Eliminar y desinstalar Squid Proxy por completo?"; then
        tc_squid_stop
        apt-get remove --purge -y squid squid3 >/dev/null 2>&1 || true
        rm -rf /etc/squid /etc/squid3
        tc_msg_ok "Squid desinstalado."
    fi
    tc_pause
}

tc_squid_menu() {
    while true; do
        tc_clear
        tc_title "GESTIÓN SQUID PROXY $(tc_squid_status_mark)"

        if ! tc_squid_is_running; then
            tc_opt "1" "INSTALAR SQUID PROXY"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_squid_install ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        else
            tc_opt "1" "DESACTIVAR SQUID PROXY"
            tc_opt "2" "RECONFIGURAR PUERTOS"
            tc_opt "3" "REINICIAR SERVICIO"
            tc_opt "4" "DESINSTALAR SQUID"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_squid_stop ;;
                2|02) tc_squid_install ;;
                3|03) systemctl restart squid >/dev/null 2>&1 || systemctl restart squid3 >/dev/null 2>&1 || true; tc_msg_ok "Squid reiniciado."; tc_pause ;;
                4|04) tc_squid_uninstall ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        fi
    done
}

