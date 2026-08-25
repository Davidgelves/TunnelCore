#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/banner.sh
#  Gestión y Personalización de Banner SSH / Dropbear
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════

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

# ── Pegar Banner Personalizado (Pegar -> Enter -> Guardado con Verificación) ──
tc_banner_paste_custom() {
    tc_clear
    tc_title "AGREGAR BANNER PERSONALIZADO"

    printf '%bPegue su código HTML o texto de Banner a continuación y presione Enter:%b\n' "$TC_YELLOW" "$TC_NC"
    printf '%b> %b' "$TC_CYAN" "$TC_NC"

    local tmp_banner="/tmp/banner_input_$$.txt"
    rm -f "$tmp_banner"

    # Esperar de forma bloqueante a que el usuario pegue y dé Enter
    local line1=""
    read -r line1
    if [[ -z "$line1" ]]; then
        tc_msg_warn "No se ingresó ningún texto."
        tc_pause
        return
    fi

    echo "$line1" > "$tmp_banner"

    # Capturar líneas adicionales si el bloque contenía saltos de línea
    while IFS= read -r -t 0.2 extra_line; do
        echo "$extra_line" >> "$tmp_banner"
    done

    # Guardar y Aplicar
    mkdir -p "/etc/tunnelcore"
    cp -f "$tmp_banner" "$TC_BANNER_FILE"
    rm -f "$tmp_banner"
    tc_banner_apply

    # Mostrar confirmación visual con lo que se pegó
    tc_clear
    tc_title "BANNER GUARDADO CON ÉXITO"
    printf '%bCONTENIDO DEL BANNER APLICADO:%b\n' "$TC_DARK_GREEN" "$TC_NC"
    tc_line
    cat "$TC_BANNER_FILE"
    echo ""
    tc_line
    tc_msg_ok "¡El banner se guardó y se aplicó correctamente a SSH y Dropbear!"
    tc_pause
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
        tc_opt "3" "RESTAURAR BANNER POR DEFECTO"
        tc_opt "4" "VER VISTA PREVIA DEL BANNER"
        tc_opt "5" "ELIMINAR BANNER"
        tc_opt "6" "DESACTIVAR BANNER"
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
                if tc_confirm "¿Restaurar el banner sencillo por defecto?"; then
                    tc_banner_set_default
                    tc_banner_apply
                    tc_msg_ok "Banner por defecto restaurado y aplicado."
                fi
                tc_pause
                ;;
            4|04)
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
            5|05)
                tc_banner_delete
                ;;
            6|06)
                tc_banner_remove
                tc_msg_ok "Banner SSH desactivado."
                tc_pause
                ;;
            0|00) break ;;
            *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
        esac
    done
}
