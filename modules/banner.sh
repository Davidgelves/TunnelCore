#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/banner.sh
#  Gestión y Personalización de Banner SSH / Dropbear
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_BANNER_FILE="/etc/tunnelcore/banner"
TC_SSHD_CONF="/etc/ssh/sshd_config"
TC_DROPBEAR_DEFAULT="/etc/default/dropbear"

# ── Banner por defecto limpio de TunnelCore ───────────────────
tc_banner_set_default() {
    mkdir -p "/etc/tunnelcore"
    cat > "$TC_BANNER_FILE" <<'EOF'
<h3 style="text-align: center;"><strong><span style="color: #00ffff;"><span style="color: #000000;">BANNER</span><br />TunnelCore<br /></span><br />By: J DAVID AG<br /></strong><strong><br /></strong></h3>
<p style="text-align: center;">&nbsp;</p>
EOF
}

tc_banner_init() {
    mkdir -p "/etc/tunnelcore"
    if [[ ! -f "$TC_BANNER_FILE" ]]; then
        tc_banner_set_default
    fi
}

tc_banner_apply() {
    tc_banner_init
    # Aplicar a OpenSSH
    if [[ -f "$TC_SSHD_CONF" ]]; then
        sed -i '/^#\?Banner /d' "$TC_SSHD_CONF"
        echo "Banner ${TC_BANNER_FILE}" >> "$TC_SSHD_CONF"
        systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true
    fi

    # Aplicar a Dropbear si está presente
    if [[ -f "$TC_DROPBEAR_DEFAULT" ]]; then
        sed -i 's|^#\?DROPBEAR_BANNER=.*|DROPBEAR_BANNER="/etc/tunnelcore/banner"|' "$TC_DROPBEAR_DEFAULT"
        systemctl restart dropbear >/dev/null 2>&1 || service dropbear restart >/dev/null 2>&1 || true
    fi
}

tc_banner_remove() {
    # Remover de OpenSSH
    if [[ -f "$TC_SSHD_CONF" ]]; then
        sed -i '/^#\?Banner /d' "$TC_SSHD_CONF"
        systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true
    fi

    # Remover de Dropbear
    if [[ -f "$TC_DROPBEAR_DEFAULT" ]]; then
        sed -i 's|^#\?DROPBEAR_BANNER=.*|DROPBEAR_BANNER=""|' "$TC_DROPBEAR_DEFAULT"
        systemctl restart dropbear >/dev/null 2>&1 || service dropbear restart >/dev/null 2>&1 || true
    fi
}

tc_banner_delete() {
    if tc_confirm "¿Está seguro de eliminar el archivo de banner?"; then
        tc_banner_remove
        rm -f "$TC_BANNER_FILE"
        tc_msg_ok "Banner eliminado por completo."
    fi
    tc_pause
}

# ── Pegar Banner Personalizado (Pegar -> Guardar / Cancelar) ──
tc_banner_paste_custom() {
    tc_clear
    tc_title "AGREGAR BANNER PERSONALIZADO"

    printf '%bPegue su código HTML o texto de Banner a continuación:%b\n' "$TC_YELLOW" "$TC_NC"
    printf '%b(Haga clic derecho o Ctrl+Shift+V para pegar y presione Enter)%b\n\n' "$TC_DARK_GREEN" "$TC_NC"

    local tmp_banner="/tmp/banner_input_$$"
    > "$tmp_banner"

    # Leer primera línea bloqueante
    read -r first_line
    if [[ -n "$first_line" ]]; then
        echo "$first_line" >> "$tmp_banner"
        # Capturar líneas adicionales si se pegó un bloque multilínea
        while IFS= read -r -t 0.3 next_line; do
            echo "$next_line" >> "$tmp_banner"
        done
    fi

    if [[ ! -s "$tmp_banner" ]]; then
        rm -f "$tmp_banner"
        tc_msg_warn "No se ingresó ningún texto."
        tc_pause
        return
    fi

    # Limpiar cualquier resto en el buffer de entrada antes de mostrar el menú
    while read -r -t 0.1 _flush; do :; done

    # Mostrar vista previa y preguntar si desea Guardar o Cancelar
    tc_clear
    tc_title "VISTA PREVIA DEL BANNER"
    cat "$tmp_banner"
    echo ""
    tc_line
    tc_opt "1" "GUARDAR Y APLICAR BANNER"
    tc_opt "0" "CANCELAR"
    tc_line
    tc_prompt
    read -r choice
    choice="$(echo "$choice" | tr -d '\r\n[:space:]')"

    case "$choice" in
        1|01)
            mkdir -p "/etc/tunnelcore"
            cp -f "$tmp_banner" "$TC_BANNER_FILE"
            rm -f "$tmp_banner"
            tc_banner_apply
            tc_msg_ok "¡Banner guardado y aplicado con éxito!"
            tc_pause
            ;;
        *)
            rm -f "$tmp_banner"
            tc_msg_warn "Operación cancelada. El banner no se modificó."
            tc_pause
            ;;
    esac
}

tc_banner_menu() {
    while true; do
        tc_clear
        tc_title "CONFIGURACIÓN DE BANNER SSH"

        local banner_active="[OFF]"
        if grep -qE "^Banner /etc/tunnelcore/banner" "$TC_SSHD_CONF" 2>/dev/null && [[ -f "$TC_BANNER_FILE" ]]; then
            banner_active="${TC_GREEN}[ON]${TC_NC}"
        else
            banner_active="${TC_RED}[OFF]${TC_NC}"
        fi

        printf '%bESTADO DEL BANNER:%b %b\n' "$TC_DARK_GREEN" "$TC_NC" "$banner_active"
        tc_line
        tc_opt "1" "ACTIVAR / APLICAR BANNER ACTUAL"
        tc_opt "2" "PEGAR BANNER PERSONALIZADO (HTML / TEXTO)"
        tc_opt "3" "EDITAR CÓDIGO CON NANO"
        tc_opt "4" "RESTAURAR BANNER POR DEFECTO"
        tc_opt "5" "VER VISTA PREVIA DEL BANNER"
        tc_opt "6" "ELIMINAR BANNER"
        tc_opt "7" "DESACTIVAR BANNER"
        tc_line
        tc_opt "0" "$(_t 'back')"
        tc_line
        tc_prompt
        read -r opt

        case "$opt" in
            1|01)
                tc_banner_apply
                tc_msg_ok "Banner SSH activado y aplicado."
                tc_pause
                ;;
            2|02)
                tc_banner_paste_custom
                ;;
            3|03)
                tc_banner_init
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
                if tc_confirm "¿Restaurar el banner sencillo por defecto?"; then
                    tc_banner_set_default
                    tc_banner_apply
                    tc_msg_ok "Banner por defecto restaurado y aplicado."
                fi
                tc_pause
                ;;
            5|05)
                tc_clear
                tc_title "VISTA PREVIA DEL BANNER"
                if [[ -f "$TC_BANNER_FILE" ]]; then
                    cat "$TC_BANNER_FILE"
                    echo ""
                else
                    tc_msg_warn "No existe ningún banner creado."
                fi
                tc_line
                tc_pause
                ;;
            6|06)
                tc_banner_delete
                ;;
            7|07)
                tc_banner_remove
                tc_msg_ok "Banner SSH desactivado."
                tc_pause
                ;;
            0|00) break ;;
            *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
        esac
    done
}
