#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/banner.sh
#  Gestión y Editor Avanzado de Banner SSH / Dropbear
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_BANNER_FILE="/etc/tunnelcore/banner"
TC_SSHD_CONF="/etc/ssh/sshd_config"

tc_banner_init() {
    mkdir -p "/etc/tunnelcore"
    if [[ ! -f "$TC_BANNER_FILE" ]]; then
        tc_banner_template_1 "TUNNELCORE VPS" "PROHIBIDO TORRENT / SPAM / MULTICUENTA"
    fi
}

tc_banner_apply() {
    tc_banner_init
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

tc_banner_template_1() {
    local t="${1:-BIENVENIDO A TUNNELCORE}" w="${2:-PROHIBIDO SPAM / TORRENT}"
    cat > "$TC_BANNER_FILE" <<EOF
<font color="#00ff7f"><b>================================================</b></font><br>
<font color="#4ce4ff"><b>          ${t}        </b></font><br>
<font color="#00ff7f"><b>================================================</b></font><br>
<font color="#ffffff">${w}</font><br>
<font color="#00ff7f"><b>================================================</b></font>
EOF
}

tc_banner_template_2() {
    local t="${1:-TUNNELCORE VIP SERVER}" w="${2:-DISFRUTA TU CONEXION PREMIUM}"
    cat > "$TC_BANNER_FILE" <<EOF
<font color="#ff0055"><b>╔══════════════════════════════════════════════╗</b></font><br>
<font color="#ffcc00"><b>║          ${t}         ║</b></font><br>
<font color="#ff0055"><b>╚══════════════════════════════════════════════╝</b></font><br>
<font color="#00ffff">★ ${w} ★</font><br>
<font color="#ff0055"><b>════════════════════════════════════════════════</b></font>
EOF
}

tc_banner_template_3() {
    local t="${1:-TUNNELCORE ACCESS}"
    cat > "$TC_BANNER_FILE" <<EOF
================================================
           ${t}
================================================
 * Prohibido Spam / Torrent / Multicuentas
 * Soporte disponible con su proveedor
================================================
EOF
}

tc_banner_quick_text() {
    tc_clear
    tc_title "CREAR BANNER RÁPIDO"

    local title warning
    printf '%bTítulo / Nombre de su servidor:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r title
    [[ -z "$title" ]] && title="TUNNELCORE SERVER"

    printf '%bMensaje de advertencia o bienvenida:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r warning
    [[ -z "$warning" ]] && warning="PROHIBIDO TORRENT / SPAM"

    printf '\n%bSeleccionar estilo de plantilla:%b\n' "$TC_WHITE" "$TC_NC"
    tc_opt "1" "Estilo Neón Cyan / Verde HTML (Recomendado para apps VPN)"
    tc_opt "2" "Estilo VIP Dorado / Fucsia HTML"
    tc_opt "3" "Estilo Texto Plano Clásico"
    tc_prompt "Opción [1-3]"
    read -r style_opt

    case "$style_opt" in
        2) tc_banner_template_2 "$title" "$warning" ;;
        3) tc_banner_template_3 "$title" ;;
        *) tc_banner_template_1 "$title" "$warning" ;;
    esac

    tc_banner_apply
    tc_msg_ok "Banner generado y aplicado a OpenSSH."
    tc_pause
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
        tc_opt "1" "ACTIVAR / APLICAR BANNER ACTUAL"
        tc_opt "2" "CREADOR RÁPIDO CON PLANTILLAS Y COLORES"
        tc_opt "3" "EDITAR CÓDIGO HTML MANUALMENTE (nano)"
        tc_opt "4" "VER VISTA PREVIA DEL BANNER"
        tc_opt "5" "DESACTIVAR BANNER"
        tc_line
        tc_opt "0" "$(_t 'back')"
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
                tc_banner_quick_text
                ;;
            3|03)
                tc_clear
                tc_title "EDITAR BANNER (Guardar: Ctrl+O, Salir: Ctrl+X)"
                if command -v nano >/dev/null 2>&1; then
                    nano "$TC_BANNER_FILE"
                else
                    vi "$TC_BANNER_FILE"
                fi
                tc_banner_apply
                tc_msg_ok "Banner actualizado y aplicado."
                tc_pause
                ;;
            4|04)
                tc_clear
                tc_title "VISTA PREVIA DEL BANNER"
                cat "$TC_BANNER_FILE"
                tc_line
                tc_pause
                ;;
            5|05)
                tc_banner_remove
                tc_msg_ok "Banner SSH desactivado."
                tc_pause
                ;;
            0|00) break ;;
            *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
        esac
    done
}
