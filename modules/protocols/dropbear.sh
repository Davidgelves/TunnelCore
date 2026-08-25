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

tc_dropbear_get_port() {
    if [[ -f "$TC_DROPBEAR_DEFAULT" ]]; then
        grep -oE '^DROPBEAR_PORT=[0-9]+' "$TC_DROPBEAR_DEFAULT" | cut -d'=' -f2 || echo "90"
    else
        echo "90"
    fi
}

tc_dropbear_install() {
    tc_clear
    tc_title "INSTALAR DROPBEAR SSH"

    local port
    printf '%bPuerto para Dropbear [Enter = 90]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r port
    [[ -z "$port" ]] && port="90"

    if ! tc_valid_port "$port"; then
        tc_msg_err "Puerto no válido."
        tc_pause
        return
    fi

    if tc_port_in_use "$port"; then
        tc_msg_warn "El puerto $port ya está en uso."
        if ! tc_confirm "¿Continuar de todos modos?"; then
            return
        fi
    fi

    tc_apt_install dropbear

    if [[ -f "$TC_DROPBEAR_DEFAULT" ]]; then
        sed -i 's/NO_START=1/NO_START=0/g' "$TC_DROPBEAR_DEFAULT"
        sed -i "s/DROPBEAR_PORT=.*/DROPBEAR_PORT=${port}/g" "$TC_DROPBEAR_DEFAULT"
        sed -i 's/DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS=""/g' "$TC_DROPBEAR_DEFAULT"
    else
        cat > "$TC_DROPBEAR_DEFAULT" <<EOF
NO_START=0
DROPBEAR_PORT=${port}
DROPBEAR_EXTRA_ARGS=""
DROPBEAR_BANNER=""
DROPBEAR_RECEIVE_WINDOW=65536
EOF
    fi

    # Registrar shells válidos para que Dropbear y PAM permitan autenticar usuarios
    grep -qxF "/bin/false" /etc/shells 2>/dev/null || echo "/bin/false" >> /etc/shells
    grep -qxF "/usr/sbin/nologin" /etc/shells 2>/dev/null || echo "/usr/sbin/nologin" >> /etc/shells

    if [[ ! -f /etc/pam.d/dropbear ]]; then
        mkdir -p /etc/pam.d
        cat > /etc/pam.d/dropbear <<'EOF'
@include common-auth
@include common-account
@include common-password
@include common-session
EOF
    fi

    # Configurar PasswordAuthentication en SSH si no estaba
    if [[ -f /etc/ssh/sshd_config ]]; then
        grep -q "^PasswordAuthentication" /etc/ssh/sshd_config || echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
    fi

    systemctl enable dropbear >/dev/null 2>&1 || true
    systemctl restart dropbear >/dev/null 2>&1 || service dropbear restart >/dev/null 2>&1 || true

    if tc_dropbear_is_running; then
        tc_msg_ok "Dropbear SSH activo en puerto: $port"
    else
        tc_msg_err "Error al iniciar Dropbear. Verifique que el puerto no esté en conflicto."
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
        local cur_port
        cur_port="$(tc_dropbear_get_port)"

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
            printf '%bPUERTO DROPBEAR:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$cur_port" "$TC_NC"
            tc_line
            tc_opt "1" "DESACTIVAR DROPBEAR"
            tc_opt "2" "CAMBIAR PUERTO"
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
