#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/banner.sh
#  Gestión de Banner SSH / Dropbear
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_BANNER_FILE="/etc/tunnelcore/banner"
TC_SSHD_CONF="/etc/ssh/sshd_config"

tc_banner_init() {
    mkdir -p "/etc/tunnelcore"
    if [[ ! -f "$TC_BANNER_FILE" ]]; then
        cat > "$TC_BANNER_FILE" <<'EOF'
<font color="#00ff7f"><b>========================================</b></font><br>
<font color="#4ce4ff"><b>           BIENVENIDO A TUNNELCORE      </b></font><br>
<font color="#00ff7f"><b>========================================</b></font><br>
<font color="#ffffff">PROHIBIDO SPAM / TORRENT / MULTICUENTA</font><br>
<font color="#00ff7f"><b>========================================</b></font>
EOF
    fi
}

tc_banner_apply() {
    tc_banner_init
    # Configurar OpenSSH
    if [[ -f "$TC_SSHD_CONF" ]]; then
        sed -i '/^#\?Banner /d' "$TC_SSHD_CONF"
        echo "Banner ${TC_BANNER_FILE}" >> "$TC_SSHD_CONF"
        systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true
    fi
}

tc_banner_remove() {
    if [[ -f "$TC_SSHD_CONF" ]]; then
        sed -i '/^#\?Banner /d' "$TC_SSHD_CONF"
        systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true
    fi
}

tc_banner_menu() {
    tc_banner_init
    while true; do
        tc_clear
        tc_title "CONFIGURACIÓN DE BANNER SSH"

        local banner_active="[OFF]"
        if grep -qE "^Banner /etc/tunnelcore/banner" "$TC_SSHD_CONF" 2>/dev/null; then
            banner_active="${TC_GREEN}[ON]${TC_NC}"
        else
            banner_active="${TC_RED}[OFF]${TC_NC}"
        fi

        printf '%bESTADO DEL BANNER:%b %b\n' "$TC_DARK_GREEN" "$TC_NC" "$banner_active"
        tc_line
        tc_opt "1" "ACTIVAR / APLICAR BANNER SSH"
        tc_opt "2" "EDITAR CONTENIDO DEL BANNER"
        tc_opt "3" "VER BANNER ACTUAL"
        tc_opt "4" "DESACTIVAR BANNER"
        tc_line
        tc_opt "0" "VOLVER"
        tc_line
        tc_prompt
        read -r opt

        case "$opt" in
            1|01)
                tc_banner_apply
                tc_msg_ok "Banner SSH activado."
                tc_pause
                ;;
            2|02)
                tc_clear
                tc_title "EDITAR BANNER (Guardar con nano o vi)"
                if command -v nano >/dev/null 2>&1; then
                    nano "$TC_BANNER_FILE"
                else
                    vi "$TC_BANNER_FILE"
                fi
                tc_banner_apply
                tc_msg_ok "Banner actualizado y aplicado."
                tc_pause
                ;;
            3|03)
                tc_clear
                tc_title "VISTA PREVIA DEL BANNER"
                cat "$TC_BANNER_FILE"
                tc_line
                tc_pause
                ;;
            4|04)
                tc_banner_remove
                tc_msg_ok "Banner SSH desactivado."
                tc_pause
                ;;
            0|00) break ;;
            *) tc_msg_err "Opción no válida."; sleep 1 ;;
        esac
    done
}

