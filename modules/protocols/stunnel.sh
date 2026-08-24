#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/stunnel.sh
#  Gestión de Stunnel4 (SSL / TLS Tunnel)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_STUNNEL_CONF="/etc/stunnel/stunnel.conf"
TC_STUNNEL_CERT="/etc/stunnel/stunnel.pem"

tc_stunnel_is_installed() {
    command -v stunnel4 >/dev/null 2>&1 || command -v stunnel >/dev/null 2>&1
}

tc_stunnel_is_running() {
    systemctl is-active --quiet stunnel4 2>/dev/null || systemctl is-active --quiet stunnel 2>/dev/null || pgrep -x stunnel4 >/dev/null 2>&1
}

tc_stunnel_status_mark() {
    if tc_stunnel_is_running; then
        printf '%b[ON]%b' "$TC_GREEN" "$TC_NC"
    elif tc_stunnel_is_installed; then
        printf '%b[OFF]%b' "$TC_RED" "$TC_NC"
    else
        printf '%b[NO INSTALADO]%b' "$TC_YELLOW" "$TC_NC"
    fi
}

tc_stunnel_gen_cert() {
    mkdir -p /etc/stunnel
    if [[ ! -f "$TC_STUNNEL_CERT" ]]; then
        openssl req -new -x509 -days 3650 -nodes \
            -subj "/C=US/ST=TunnelCore/L=VPN/O=TunnelCore/CN=tunnelcore.ssl" \
            -out "$TC_STUNNEL_CERT" -keyout "$TC_STUNNEL_CERT" >/dev/null 2>&1
        chmod 600 "$TC_STUNNEL_CERT"
    fi
}

tc_stunnel_install() {
    tc_clear
    tc_title "INSTALAR STUNNEL4 (SSL TUNNEL)"

    local port target
    printf '%bPuerto de escucha SSL [Enter = 443]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r port
    [[ -z "$port" ]] && port="443"

    if ! tc_valid_port "$port"; then
        tc_msg_err "Puerto inválido."
        tc_pause
        return
    fi

    printf '%bPuerto destino local (SSH=22, Dropbear=110/443, WS=80) [Enter = 22]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r target
    [[ -z "$target" ]] && target="22"

    tc_apt_install stunnel4 openssl
    tc_stunnel_gen_cert

    cat > "$TC_STUNNEL_CONF" <<EOF
cert = ${TC_STUNNEL_CERT}
client = no
pid = /var/run/stunnel4.pid

[ssh-ssl]
accept = ${port}
connect = 127.0.0.1:${target}
EOF

    # Habilitar en /etc/default/stunnel4
    if [[ -f /etc/default/stunnel4 ]]; then
        sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4
    fi

    systemctl enable stunnel4 >/dev/null 2>&1 || true
    systemctl restart stunnel4 >/dev/null 2>&1 || service stunnel4 restart >/dev/null 2>&1 || true

    if tc_stunnel_is_running; then
        tc_msg_ok "Stunnel4 SSL activo en puerto $port redirigiendo a 127.0.0.1:$target."
    else
        tc_msg_err "Stunnel4 no pudo iniciar."
    fi
    tc_pause
}

tc_stunnel_stop() {
    systemctl stop stunnel4 >/dev/null 2>&1 || true
    systemctl disable stunnel4 >/dev/null 2>&1 || true
    tc_msg_ok "Stunnel4 detenido."
    tc_pause
}

tc_stunnel_menu() {
    while true; do
        tc_clear
        tc_title "GESTIÓN STUNNEL (SSL TUNNEL) $(tc_stunnel_status_mark)"

        if ! tc_stunnel_is_running; then
            tc_opt "1" "INSTALAR / ACTIVAR STUNNEL"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_stunnel_install ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        else
            tc_opt "1" "DESACTIVAR STUNNEL"
            tc_opt "2" "RECONFIGURAR PUERTO / DESTINO"
            tc_opt "3" "REINICIAR SERVICIO"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_stunnel_stop ;;
                2|02) tc_stunnel_install ;;
                3|03) systemctl restart stunnel4 >/dev/null 2>&1 && tc_msg_ok "Stunnel4 reiniciado." && tc_pause ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        fi
    done
}

