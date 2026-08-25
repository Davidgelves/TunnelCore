#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/banner.sh
#  Gestión y Personalización de Banner SSH / Dropbear (Sin Nano)
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

# ── Pegar Banner Personalizado en Terminal (Directo vía /dev/tty) ──
tc_banner_paste_custom() {
    tc_clear
    tc_title "AGREGAR BANNER PERSONALIZADO"

    local tmp_file="/tmp/tc_banner_tmp_$$.html"
    rm -f "$tmp_file"

    python3 -c '
import sys, os, select

try:
    tty = open("/dev/tty", "r", encoding="utf-8", errors="replace")
except Exception:
    tty = sys.stdin

print("\033[1;33mPegue su código HTML o texto de Banner a continuación y presione Enter:\033[0m\n")

lines = []
first = tty.readline()
if first and first.strip():
    lines.append(first)
    while select.select([tty], [], [], 0.3)[0]:
        extra = tty.readline()
        if not extra:
            break
        lines.append(extra)

content = "".join(lines).strip()
if not content:
    sys.exit(2)

with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write(content + "\n")

sys.exit(0)
' "$tmp_file"

    local ret=$?
    if [[ $ret -ne 0 || ! -s "$tmp_file" ]]; then
        rm -f "$tmp_file"
        tc_msg_warn "No se ingresó ningún texto."
        tc_pause
        return
    fi

    # Mostrar vista previa y preguntar si desea Guardar o Cancelar
    tc_clear
    tc_title "VISTA PREVIA DEL BANNER"
    cat "$tmp_file"
    echo ""
    tc_line
    tc_opt "1" "GUARDAR Y APLICAR BANNER"
    tc_opt "0" "CANCELAR"
    tc_line
    tc_prompt
    read -r choice < /dev/tty
    choice="$(echo "$choice" | tr -d '\r\n[:space:]')"

    case "$choice" in
        1|01)
            mkdir -p "/etc/tunnelcore"
            cp -f "$tmp_file" "$TC_BANNER_FILE"
            rm -f "$tmp_file"
            tc_banner_apply
            echo ""
            tc_msg_ok "¡Banner guardado y aplicado con éxito!"
            tc_pause
            ;;
        *)
            rm -f "$tmp_file"
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
