#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/hysteria.sh
#  Gestión de Hysteria UDP Tunnel
#  Usa el binario oficial de apernet/hysteria
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_HYST_BIN="/usr/local/bin/hysteria1"
TC_HYST_DIR="/etc/tunnelcore/hysteria"
TC_HYST_CONF="${TC_HYST_DIR}/config.json"
TC_HYST_ENV="${TC_HYST_DIR}/hysteria.env"
TC_HYST_CERT="${TC_HYST_DIR}/server.crt"
TC_HYST_KEY="${TC_HYST_DIR}/server.key"
TC_HYST_SERVICE="/etc/systemd/system/hysteria-server.service"
TC_HYST_IPTABLES="${TC_HYST_DIR}/iptables.sh"

tc_hyst_is_installed() {
    [[ -x "$TC_HYST_BIN" && -f "$TC_HYST_CONF" ]]
}

tc_hyst_is_running() {
    systemctl is-active --quiet hysteria-server 2>/dev/null
}

tc_hyst_status_mark() {
    if tc_hyst_is_running; then
        printf '%b[ON]%b' "$TC_GREEN" "$TC_NC"
    elif tc_hyst_is_installed; then
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

tc_hyst_install_bin() {
    tc_require_cmd "curl" "curl"
    tc_require_cmd "openssl" "openssl"
    tc_require_cmd "iptables" "iptables"

    local arch asset
    case "$(uname -m)" in
        x86_64|amd64)       asset="hysteria-linux-amd64" ;;
        aarch64|arm64|armv8) asset="hysteria-linux-arm64" ;;
        armv7l|armhf)       asset="hysteria-linux-arm" ;;
        *)
            tc_msg_err "Arquitectura no compatible para Hysteria."
            return 1
            ;;
    esac

    local url="https://github.com/apernet/hysteria/releases/download/v1.3.5/${asset}"
    tc_msg_ok "Descargando Hysteria v1 oficial..."

    if ! tc_download "$url" "$TC_HYST_BIN" 3; then
        tc_msg_err "No se pudo descargar Hysteria."
        return 1
    fi

    chmod +x "$TC_HYST_BIN"
    mkdir -p "$TC_HYST_DIR"
    return 0
}

tc_hyst_build_auth_list() {
    local users_db="/etc/tunnelcore/users.db" pass_dir="/etc/tunnelcore/passwords"
    local u p found=0 sep=""

    if [[ ! -f "$users_db" ]]; then
        # Fallback a usuarios del sistema
        return 1
    fi

    while IFS='|' read -r u _pass _exp _lim; do
        u="$(echo "$u" | xargs)"
        [[ -z "$u" ]] && continue
        [[ -f "${pass_dir}/${u}" ]] || continue
        p="$(cat "${pass_dir}/${u}" 2>/dev/null)"
        [[ -z "$p" ]] && continue
        printf '%s      "%s:%s"\n' "$sep" "$u" "$p"
        sep=","
        found=1
    done < "$users_db"

    (( found == 1 ))
}

tc_hyst_write_config() {
    local port="$1" rules="$2" obfs="$3" auth_block
    auth_block="$(tc_hyst_build_auth_list)" || {
        tc_msg_err "No hay usuarios SSH con contraseña guardada en TunnelCore."
        return 1
    }

    mkdir -p "$TC_HYST_DIR"

    # Generar certificado autofirmado si no existe
    if [[ ! -f "$TC_HYST_CERT" || ! -f "$TC_HYST_KEY" ]]; then
        openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
            -keyout "$TC_HYST_KEY" -out "$TC_HYST_CERT" -subj "/CN=tunnelcore-hysteria" >/dev/null 2>&1
    fi

    cat > "$TC_HYST_CONF" <<EOF
{
  "listen": ":${port}",
  "cert": "${TC_HYST_CERT}",
  "key": "${TC_HYST_KEY}",
  "obfs": "${obfs}",
  "auth": {
    "mode": "passwords",
    "config": [
${auth_block}
    ]
  }
}
EOF

    cat > "$TC_HYST_ENV" <<EOF
HYST_PORT="${port}"
HYST_RULES="${rules}"
HYST_OBFS="${obfs}"
EOF

    # Helper iptables para Port Hopping
    cat > "$TC_HYST_IPTABLES" <<'EOF'
#!/bin/bash
ACTION="${1:-apply}"
ENV_FILE="/etc/tunnelcore/hysteria/hysteria.env"
CHAIN="TC_HYSTERIA"
[[ -f "$ENV_FILE" ]] && . "$ENV_FILE"

clear_rules() {
    while iptables -t nat -C PREROUTING -p udp -j "$CHAIN" >/dev/null 2>&1; do
        iptables -t nat -D PREROUTING -p udp -j "$CHAIN" >/dev/null 2>&1 || break
    done
    iptables -t nat -F "$CHAIN" >/dev/null 2>&1 || true
    iptables -t nat -X "$CHAIN" >/dev/null 2>&1 || true
}

apply_rules() {
    clear_rules
    iptables -I INPUT 1 -p udp --dport "${HYST_PORT:-36712}" -j ACCEPT >/dev/null 2>&1 || true
    [[ -z "$HYST_RULES" || "$HYST_RULES" == "none" ]] && return 0
    iptables -t nat -N "$CHAIN" >/dev/null 2>&1 || true
    iptables -t nat -I PREROUTING 1 -p udp -j "$CHAIN" >/dev/null 2>&1 || true
    local clean="${HYST_RULES// /}" item
    IFS=',' read -ra items <<< "$clean"
    for item in "${items[@]}"; do
        [[ -z "$item" || "$item" == "53" || "$item" == "5300" ]] && continue
        iptables -t nat -A "$CHAIN" -p udp --dport "$item" -j REDIRECT --to-ports "$HYST_PORT" >/dev/null 2>&1 || true
    done
}

case "$ACTION" in
    apply) apply_rules ;;
    clear) clear_rules ;;
esac
EOF
    chmod +x "$TC_HYST_IPTABLES"
    chmod 600 "$TC_HYST_CONF" "$TC_HYST_ENV" "$TC_HYST_KEY"
}

tc_hyst_write_service() {
    cat > "$TC_HYST_SERVICE" <<EOF
[Unit]
Description=TunnelCore Hysteria UDP Server
After=network.target

[Service]
Type=simple
ExecStart=${TC_HYST_BIN} -c ${TC_HYST_CONF} server
ExecStartPre=${TC_HYST_IPTABLES} apply
ExecStopPost=${TC_HYST_IPTABLES} clear
WorkingDirectory=${TC_HYST_DIR}
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable hysteria-server >/dev/null 2>&1
}

# ── Sincronizar usuarios ──────────────────────────────────────
tc_hyst_sync() {
    [[ -f "$TC_HYST_ENV" ]] || return 0
    tc_hyst_load_env
    tc_hyst_write_config "${HYST_PORT:-36712}" "${HYST_RULES:-none}" "${HYST_OBFS:-}" || return 0
    systemctl restart hysteria-server >/dev/null 2>&1 || true
}

# ── Instalar / Configurar ─────────────────────────────────────
tc_hyst_configure() {
    tc_clear
    tc_title "CONFIGURAR HYSTERIA UDP"

    if ! tc_hyst_build_auth_list >/dev/null 2>&1; then
        tc_msg_err "No hay usuarios SSH creados en TunnelCore."
        tc_msg_warn "Cree al menos un usuario en [1] Administrar Usuarios primero."
        tc_pause
        return
    fi

    local port rules obfs hop_resp
    printf '%bPuerto principal UDP [Enter = 36712]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r port
    [[ -z "$port" ]] && port="36712"

    if ! tc_valid_port "$port"; then
        tc_msg_err "Puerto inválido."
        tc_pause
        return
    fi

    if tc_confirm "¿Habilitar Port Hopping (Redirección de rangos UDP)?"; then
        printf '%bRangos UDP [ej: 20000:50000]:%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r rules
        [[ -z "$rules" ]] && rules="20000:50000"
    else
        rules="none"
    fi

    printf '%bClave de ofuscación OBFS (Enter = aleatoria):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r obfs
    [[ -z "$obfs" ]] && obfs="$(tc_rand_string 18)"

    [[ -x "$TC_HYST_BIN" ]] || tc_hyst_install_bin || { tc_pause; return; }
    tc_hyst_write_config "$port" "$rules" "$obfs" || { tc_pause; return; }
    tc_hyst_write_service

    systemctl restart hysteria-server >/dev/null 2>&1

    if tc_hyst_is_running; then
        local ip
        ip="$(tc_public_ip)"
        tc_msg_ok "Hysteria UDP configurado y activo."
        printf '\n%bDATOS DE CONEXIÓN HYSTERIA:%b\n' "$TC_YELLOW" "$TC_NC"
        printf '  %bServidor:%b %s:%s\n' "$TC_DARK_GREEN" "$TC_WHITE" "$ip" "$port"
        printf '  %bAuth:%b     Usuario y contraseña de SSH\n' "$TC_DARK_GREEN" "$TC_WHITE"
        printf '  %bOBFS:%b     %s\n' "$TC_DARK_GREEN" "$TC_GREEN" "$obfs"
        printf '  %bTLS:%b      Insecure / allowInsecure = true\n' "$TC_DARK_GREEN" "$TC_WHITE"
    else
        tc_msg_err "Hysteria no pudo iniciar. Revise 'journalctl -u hysteria-server -n 20'."
    fi
    tc_pause
}

# ── Desinstalar ───────────────────────────────────────────────
tc_hyst_uninstall() {
    tc_clear
    tc_title "DESINSTALAR HYSTERIA"
    if tc_confirm "¿Está seguro de desinstalar Hysteria?"; then
        systemctl stop hysteria-server >/dev/null 2>&1 || true
        systemctl disable hysteria-server >/dev/null 2>&1 || true
        [[ -x "$TC_HYST_IPTABLES" ]] && "$TC_HYST_IPTABLES" clear
        rm -f "$TC_HYST_SERVICE" "$TC_HYST_BIN"
        rm -rf "$TC_HYST_DIR"
        systemctl daemon-reload >/dev/null 2>&1
        tc_msg_ok "Hysteria desinstalado correctamente."
    fi
    tc_pause
}

# ── Menú Hysteria ─────────────────────────────────────────────
tc_hyst_menu() {
    while true; do
        tc_clear
        tc_hyst_load_env
        tc_title "GESTIÓN HYSTERIA UDP $(tc_hyst_status_mark)"

        if ! tc_hyst_is_installed; then
            tc_opt "1" "INSTALAR Y CONFIGURAR HYSTERIA"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_hyst_configure ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        else
            printf '%bPUERTO:%b %b%s%b  %bRANGOS:%b %b%s%b  %bOBFS:%b %b%s%b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "${HYST_PORT:-36712}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "${HYST_RULES:-none}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${HYST_OBFS:-N/A}" "$TC_NC"
            tc_line
            tc_opt "1" "RECONFIGURAR HYSTERIA"
            tc_opt "2" "SINCRONIZAR USUARIOS AHORA"
            tc_opt "3" "REINICIAR SERVICIO"
            tc_opt "4" "VER LOGS DE HYSTERIA"
            tc_opt "5" "DESINSTALAR HYSTERIA"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_hyst_configure ;;
                2|02) tc_hyst_sync && tc_msg_ok "Usuarios sincronizados." && tc_pause ;;
                3|03) systemctl restart hysteria-server >/dev/null 2>&1 && tc_msg_ok "Servicio reiniciado." && tc_pause ;;
                4|04) journalctl -u hysteria-server -n 30 --no-pager && tc_pause ;;
                5|05) tc_hyst_uninstall ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        fi
    done
}

case "${1:-}" in
    --sync) tc_hyst_sync ;;
esac

