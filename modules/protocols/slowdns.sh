#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/slowdns.sh
#  Gestión de SlowDNS (DNSTT Server)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_SLOW_DIR="/etc/tunnelcore/slowdns"
TC_SLOW_CONF="${TC_SLOW_DIR}/slowdns.conf"
TC_SLOW_KEY="${TC_SLOW_DIR}/server.key"
TC_SLOW_PUB="${TC_SLOW_DIR}/server.pub"
TC_SLOW_BIN="/usr/local/bin/dnstt-server"
TC_SLOW_SERVICE="/etc/systemd/system/slowdns.service"
TC_SLOW_IPTABLES="${TC_SLOW_DIR}/iptables.sh"
TC_SLOW_LOG="/var/log/slowdns.log"

tc_slow_is_installed() {
    [[ -x "$TC_SLOW_BIN" && -f "$TC_SLOW_CONF" ]]
}

tc_slow_is_running() {
    systemctl is-active --quiet slowdns 2>/dev/null
}

tc_slow_status_mark() {
    if tc_slow_is_running; then
        printf '%b[ON]%b' "$TC_GREEN" "$TC_NC"
    elif tc_slow_is_installed; then
        printf '%b[OFF]%b' "$TC_RED" "$TC_NC"
    else
        printf '%b[NO INSTALADO]%b' "$TC_YELLOW" "$TC_NC"
    fi
}

tc_slow_load_conf() {
    SLOW_PORT="5300"
    SLOW_TARGET="22"
    SLOW_DOMAIN=""
    SLOW_REDIR="53"
    if [[ -f "$TC_SLOW_CONF" ]]; then
        # shellcheck disable=SC1090
        . "$TC_SLOW_CONF"
    fi
}

tc_slow_save_conf() {
    mkdir -p "$TC_SLOW_DIR"
    cat > "$TC_SLOW_CONF" <<EOF
SLOW_PORT="${SLOW_PORT:-5300}"
SLOW_TARGET="${SLOW_TARGET:-22}"
SLOW_DOMAIN="${SLOW_DOMAIN:-}"
SLOW_REDIR="${SLOW_REDIR:-53}"
EOF
    chmod 600 "$TC_SLOW_CONF"
}

# ── Descargar / Compilar dnstt-server ─────────────────────────
tc_slow_download_bin() {
    tc_require_cmd "curl" "curl"
    tc_require_cmd "iptables" "iptables"

    local arch
    arch="$(tc_detect_arch)"
    local url=""

    case "$arch" in
        amd64) url="https://github.com/Davidgelves/NoxuraSSH/raw/main/Modulos/dnstt-server-amd64" ;;
        arm64) url="https://github.com/Davidgelves/NoxuraSSH/raw/main/Modulos/dnstt-server-arm64" ;;
        *)
            # Fallback o compilar si Go está disponible
            url="https://dnstt.network/dnstt-server-linux-${arch}"
            ;;
    esac

    local tmp="/tmp/dnstt-server.$$"
    tc_msg_ok "Descargando dnstt-server para arquitectura $arch..."

    if ! tc_download "$url" "$tmp" 3; then
        # Si la descarga directa falla, intentamos compilar con Go si existe
        if command -v go >/dev/null 2>&1; then
            tc_msg_warn "Intentando compilar dnstt-server con Go..."
            git clone --depth=1 https://www.bamsoftware.com/git/dnstt.git /tmp/dnstt-build-$$ >/dev/null 2>&1 || true
            if [[ -d "/tmp/dnstt-build-$$/dnstt-server" ]]; then
                (cd "/tmp/dnstt-build-$$/dnstt-server" && go build -o "$TC_SLOW_BIN") >/dev/null 2>&1 || true
                rm -rf "/tmp/dnstt-build-$$"
            fi
        fi
    else
        install -m 755 "$tmp" "$TC_SLOW_BIN"
        rm -f "$tmp"
    fi

    if [[ ! -x "$TC_SLOW_BIN" ]]; then
        tc_msg_err "No se pudo obtener el binario dnstt-server."
        return 1
    fi
    return 0
}

# ── Generar claves criptográficas ─────────────────────────────
tc_slow_gen_keys() {
    mkdir -p "$TC_SLOW_DIR"
    [[ -x "$TC_SLOW_BIN" ]] || tc_slow_download_bin || return 1
    "$TC_SLOW_BIN" -gen-key -privkey-file "$TC_SLOW_KEY" -pubkey-file "$TC_SLOW_PUB" >/dev/null 2>&1
    chmod 600 "$TC_SLOW_KEY"
    chmod 644 "$TC_SLOW_PUB"
}

# ── Helper iptables ───────────────────────────────────────────
tc_slow_write_iptables_helper() {
    mkdir -p "$TC_SLOW_DIR"
    cat > "$TC_SLOW_IPTABLES" <<'EOF'
#!/bin/bash
ACTION="${1:-apply}"
CONF="/etc/tunnelcore/slowdns/slowdns.conf"
[[ -f "$CONF" ]] && . "$CONF"

PORT="${SLOW_PORT:-5300}"
REDIR="${SLOW_REDIR:-53}"

clear_rules() {
    iptables -D INPUT -p udp --dport "$REDIR" -j ACCEPT >/dev/null 2>&1 || true
    iptables -D INPUT -p udp --dport "$PORT" -j ACCEPT >/dev/null 2>&1 || true
    while iptables -t nat -C PREROUTING -p udp -m udp --dport "$REDIR" -j REDIRECT --to-ports "$PORT" >/dev/null 2>&1; do
        iptables -t nat -D PREROUTING -p udp -m udp --dport "$REDIR" -j REDIRECT --to-ports "$PORT" >/dev/null 2>&1 || break
    done
    while iptables -t nat -C PREROUTING -p udp --dport "$REDIR" -j REDIRECT --to-ports "$PORT" >/dev/null 2>&1; do
        iptables -t nat -D PREROUTING -p udp --dport "$REDIR" -j REDIRECT --to-ports "$PORT" >/dev/null 2>&1 || break
    done
}

apply_rules() {
    clear_rules
    iptables -I INPUT 1 -p udp --dport "$REDIR" -j ACCEPT >/dev/null 2>&1 || true
    iptables -I INPUT 1 -p udp --dport "$PORT" -j ACCEPT >/dev/null 2>&1 || true
    iptables -t nat -I PREROUTING 1 -p udp -m udp --dport "$REDIR" -j REDIRECT --to-ports "$PORT" >/dev/null 2>&1 || true
}

case "$ACTION" in
    apply) apply_rules ;;
    clear) clear_rules ;;
esac
EOF
    chmod +x "$TC_SLOW_IPTABLES"
}

# ── Escribir servicio systemd ──────────────────────────────────
tc_slow_write_service() {
    tc_slow_write_iptables_helper
    cat > "$TC_SLOW_SERVICE" <<EOF
[Unit]
Description=TunnelCore SlowDNS DNSTT Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=${TC_SLOW_IPTABLES} apply
ExecStart=${TC_SLOW_BIN} -udp :${SLOW_PORT} -privkey-file ${TC_SLOW_KEY} ${SLOW_DOMAIN} 127.0.0.1:${SLOW_TARGET}
ExecStopPost=${TC_SLOW_IPTABLES} clear
Restart=always
RestartSec=3
LimitNOFILE=65535
StandardOutput=append:${TC_SLOW_LOG}
StandardError=append:${TC_SLOW_LOG}

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable slowdns >/dev/null 2>&1
}

# ── Configurar / Instalar ─────────────────────────────────────
tc_slow_configure() {
    tc_clear
    tc_title "CONFIGURAR SLOWDNS (DNSTT)"

    tc_slow_load_conf

    local domain port target
    printf '%bDominio NS (ej: ns.midominio.com):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r domain
    [[ -n "$domain" ]] && SLOW_DOMAIN="$domain"

    if [[ -z "$SLOW_DOMAIN" ]]; then
        tc_msg_err "Debe ingresar un subdominio NS válido apuntando a la IP de esta VPS."
        tc_pause
        return
    fi

    printf '%bPuerto de escucha UDP [Enter = 5300]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r port
    [[ -n "$port" ]] && SLOW_PORT="$port"

    printf '%bPuerto destino local (SSH=22, Dropbear=110/443) [Enter = 22]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r target
    [[ -n "$target" ]] && SLOW_TARGET="$target"

    tc_slow_download_bin || { tc_pause; return; }
    [[ -f "$TC_SLOW_KEY" && -f "$TC_SLOW_PUB" ]] || tc_slow_gen_keys || { tc_pause; return; }

    tc_slow_save_conf
    tc_slow_write_service

    systemctl restart slowdns >/dev/null 2>&1

    if tc_slow_is_running; then
        tc_msg_ok "SlowDNS configurado y en ejecución."
        printf '\n%bClave Pública (para cliente):%b %b%s%b\n' \
            "$TC_YELLOW" "$TC_NC" "$TC_GREEN" "$(cat "$TC_SLOW_PUB" 2>/dev/null)" "$TC_NC"
    else
        tc_msg_err "SlowDNS se configuró pero no inició. Revise 'journalctl -u slowdns -n 20'."
    fi
    tc_pause
}

# ── Mostrar claves ────────────────────────────────────────────
tc_slow_show_keys() {
    tc_clear
    tc_title "CLAVES CRIPTOGRÁFICAS SLOWDNS"
    if [[ -f "$TC_SLOW_PUB" ]]; then
        printf '%bCLAVE PÚBLICA (Cliente):%b\n%b%s%b\n\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$(cat "$TC_SLOW_PUB")" "$TC_NC"
    else
        tc_msg_warn "No se encontró clave pública."
    fi
    if [[ -f "$TC_SLOW_KEY" ]]; then
        printf '%bCLAVE PRIVADA (Servidor):%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$TC_SLOW_KEY" "$TC_NC"
    fi
    tc_line
    tc_pause
}

# ── Desinstalar ───────────────────────────────────────────────
tc_slow_uninstall() {
    tc_clear
    tc_title "DESINSTALAR SLOWDNS"

    if tc_confirm "¿Está seguro de desinstalar SlowDNS?"; then
        systemctl stop slowdns >/dev/null 2>&1 || true
        systemctl disable slowdns >/dev/null 2>&1 || true
        [[ -x "$TC_SLOW_IPTABLES" ]] && "$TC_SLOW_IPTABLES" clear
        rm -f "$TC_SLOW_SERVICE" "$TC_SLOW_BIN" "$TC_SLOW_LOG"
        rm -rf "$TC_SLOW_DIR"
        systemctl daemon-reload >/dev/null 2>&1
        tc_msg_ok "SlowDNS desinstalado por completo."
    fi
    tc_pause
}

# ── Menú SlowDNS ──────────────────────────────────────────────
tc_slow_menu() {
    while true; do
        tc_clear
        tc_slow_load_conf
        tc_title "GESTIÓN SLOWDNS $(tc_slow_status_mark)"

        if ! tc_slow_is_installed; then
            tc_opt "1" "INSTALAR Y CONFIGURAR SLOWDNS"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_slow_configure ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        else
            printf '%bDOMINIO NS:%b %b%s%b  %bDESTINO:%b %b127.0.0.1:%s%b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "${SLOW_DOMAIN:-N/A}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${SLOW_TARGET:-22}" "$TC_NC"
            tc_line
            tc_opt "1" "RECONFIGURAR SLOWDNS"
            tc_opt "2" "VER CLAVES SLOWDNS"
            tc_opt "3" "GENERAR NUEVO PAR DE CLAVES"
            tc_opt "4" "REINICIAR SERVICIO"
            tc_opt "5" "VER LOGS DE SLOWDNS"
            tc_opt "6" "DESINSTALAR SLOWDNS"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_slow_configure ;;
                2|02) tc_slow_show_keys ;;
                3|03) tc_slow_gen_keys && systemctl restart slowdns && tc_msg_ok "Claves regeneradas y servicio reiniciado." && tc_pause ;;
                4|04) systemctl restart slowdns >/dev/null 2>&1 && tc_msg_ok "Servicio reiniciado." && tc_pause ;;
                5|05) journalctl -u slowdns -n 30 --no-pager && tc_pause ;;
                6|06) tc_slow_uninstall ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        fi
    done
}

