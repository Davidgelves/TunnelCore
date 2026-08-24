#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/dropbear.sh
#  Gestión de Dropbear SSH
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_DROPBEAR_DEFAULT="/etc/default/dropbear"

tc_dropbear_is_installed() {
    command -v dropbear >/dev/null 2>&1
}

tc_dropbear_is_running() {
    systemctl is-active --quiet dropbear 2>/dev/null || pgrep -x dropbear >/dev/null 2>&1
}

tc_dropbear_status_mark() {
    if tc_dropbear_is_running; then
        printf '%b[ON]%b' "$TC_GREEN" "$TC_NC"
    elif tc_dropbear_is_installed; then
        printf '%b[OFF]%b' "$TC_RED" "$TC_NC"
    else
        printf '%b[NO INSTALADO]%b' "$TC_YELLOW" "$TC_NC"
    fi
}

tc_dropbear_install() {
    tc_clear
    tc_title "INSTALAR DROPBEAR SSH"

    local port extra_port
    printf '%bPuerto principal para Dropbear [Enter = 110]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r port
    [[ -z "$port" ]] && port="110"

    printf '%bPuerto secundario (opcional) [Enter = 443]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r extra_port
    [[ -z "$extra_port" ]] && extra_port="443"

    tc_apt_install dropbear

    if [[ -f "$TC_DROPBEAR_DEFAULT" ]]; then
        sed -i 's/NO_START=1/NO_START=0/g' "$TC_DROPBEAR_DEFAULT"
        sed -i "s/DROPBEAR_PORT=.*/DROPBEAR_PORT=${port}/g" "$TC_DROPBEAR_DEFAULT"
        sed -i "s/DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS=\"-p ${extra_port}\"/g" "$TC_DROPBEAR_DEFAULT"
    fi

    # Configurar PasswordAuthentication en SSH si no estaba
    if [[ -f /etc/ssh/sshd_config ]]; then
        grep -q "^PasswordAuthentication" /etc/ssh/sshd_config || echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
    fi

    systemctl enable dropbear >/dev/null 2>&1 || true
    systemctl restart dropbear >/dev/null 2>&1 || service dropbear restart >/dev/null 2>&1 || true

    if tc_dropbear_is_running; then
        tc_msg_ok "Dropbear SSH activo en puertos: $port, $extra_port"
    else
        tc_msg_err "Error al iniciar Dropbear."
    fi
    tc_pause
}

tc_dropbear_stop() {
    systemctl stop dropbear >/dev/null 2>&1 || service dropbear stop >/dev/null 2>&1 || true
    systemctl disable dropbear >/dev/null 2>&1 || true
    tc_msg_ok "Dropbear detenido."
    tc_pause
}

tc_dropbear_menu() {
    while true; do
        tc_clear
        tc_title "GESTIÓN DROPBEAR SSH $(tc_dropbear_status_mark)"

        if ! tc_dropbear_is_running; then
            tc_opt "1" "INSTALAR / ACTIVAR DROPBEAR"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_dropbear_install ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        else
            tc_opt "1" "DESACTIVAR DROPBEAR"
            tc_opt "2" "RECONFIGURAR PUERTOS"
            tc_opt "3" "REINICIAR SERVICIO"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_dropbear_stop ;;
                2|02) tc_dropbear_install ;;
                3|03) systemctl restart dropbear >/dev/null 2>&1 || service dropbear restart >/dev/null 2>&1 || true; tc_msg_ok "Dropbear reiniciado."; tc_pause ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        fi
    done
}

