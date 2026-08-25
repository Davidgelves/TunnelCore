#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/slowdns.sh
#  Gestión de SlowDNS (DNSTT Server)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════

TC_SLOW_DIR="/etc/tunnelcore/slowdns"
TC_SLOW_CONF="${TC_SLOW_DIR}/slowdns.conf"
TC_SLOW_KEY="${TC_SLOW_DIR}/server.key"
TC_SLOW_PUB="${TC_SLOW_DIR}/server.pub"
TC_SLOW_BIN="/usr/local/bin/dnstt-server"
TC_SLOW_SERVICE="/etc/systemd/system/slowdns.service"
TC_SLOW_IPTABLES="${TC_SLOW_DIR}/iptables.sh"
TC_SLOW_LOG="/var/log/slowdns.log"
TC_SLOW_PORT_DEFAULT="5300"
TC_SLOW_TRAFFIC_DEFAULT="22"
TC_SLOW_DOMAIN_DEFAULT=""

tc_slow_is_installed() {
    [[ -x "$TC_SLOW_BIN" && -f "$TC_SLOW_CONF" ]]
}

tc_slow_is_running() {
    systemctl is-active --quiet slowdns 2>/dev/null
}

tc_slow_status_mark() {
    if tc_slow_is_running; then
        printf '%b[ON]%b' "$TC_GREEN" "$TC_NC"
    elif [[ -f "$TC_SLOW_CONF" ]]; then
        printf '%b[OFF]%b' "$TC_RED" "$TC_NC"
    else
        printf '%b[NO INSTALADO]%b' "$TC_YELLOW" "$TC_NC"
    fi
}

tc_slow_load_conf() {
    SLOW_PORT="$TC_SLOW_PORT_DEFAULT"
    SLOW_TRAFFIC="$TC_SLOW_TRAFFIC_DEFAULT"
    SLOW_DOMAIN="$TC_SLOW_DOMAIN_DEFAULT"
    SLOW_REDIRECT="53"
    if [[ -f "$TC_SLOW_CONF" ]]; then
        # shellcheck disable=SC1090
        . "$TC_SLOW_CONF" 2>/dev/null || true
    fi
}

tc_slow_save_conf() {
    mkdir -p "$TC_SLOW_DIR"
    cat > "$TC_SLOW_CONF" <<EOF
SLOW_PORT="${SLOW_PORT:-$TC_SLOW_PORT_DEFAULT}"
SLOW_TRAFFIC="${SLOW_TRAFFIC:-$TC_SLOW_TRAFFIC_DEFAULT}"
SLOW_DOMAIN="${SLOW_DOMAIN:-$TC_SLOW_DOMAIN_DEFAULT}"
SLOW_REDIRECT="${SLOW_REDIRECT:-53}"
EOF
    chmod 644 "$TC_SLOW_CONF"
}

# ── Descargar dnstt-server con mirrors oficiales y redundantes ──
tc_slow_download_bin() {
    local arch
    arch="$(tc_detect_arch)"
    local tmp="/tmp/dnstt-server.$$"
    rm -f "$tmp"

    local mirrors=()
    if [[ "$arch" == "amd64" ]]; then
        mirrors=(
            "https://dnstt.network/dnstt-server-linux-amd64"
            "https://github.com/alexandre01-dev/dnstt/releases/download/v1.0/dnstt-server-linux-amd64"
            "https://github.com/darxssh/SlowDNS/raw/main/dnstt-server"
        )
    elif [[ "$arch" == "arm64" ]]; then
        mirrors=(
            "https://dnstt.network/dnstt-server-linux-arm64"
            "https://github.com/alexandre01-dev/dnstt/releases/download/v1.0/dnstt-server-linux-arm64"
        )
    else
        mirrors=(
            "https://dnstt.network/dnstt-server-linux-arm"
        )
    fi

    tc_msg_ok "Descargando dnstt-server para arquitectura $arch..."
    local downloaded=0
    for u in "${mirrors[@]}"; do
        if curl -fsSL --connect-timeout 5 --max-time 20 -o "$tmp" "$u" 2>/dev/null && [[ -s "$tmp" ]]; then
            downloaded=1
            break
        elif wget -q --timeout=10 -O "$tmp" "$u" 2>/dev/null && [[ -s "$tmp" ]]; then
            downloaded=1
            break
        fi
    done

    if [[ "$downloaded" -eq 1 && -s "$tmp" ]]; then
        chmod +x "$tmp"
        mv -f "$tmp" "$TC_SLOW_BIN"
        chmod +x "$TC_SLOW_BIN"
        return 0
    else
        tc_msg_err "No se pudo descargar dnstt-server."
        return 1
    fi
}

tc_slow_generate_keys() {
    mkdir -p "$TC_SLOW_DIR"
    [[ -x "$TC_SLOW_BIN" ]] || tc_slow_download_bin || return 1
    "$TC_SLOW_BIN" -gen-key -privkey-file "$TC_SLOW_KEY" -pubkey-file "$TC_SLOW_PUB" >/dev/null 2>&1
    chmod 600 "$TC_SLOW_KEY"
    chmod 644 "$TC_SLOW_PUB"
}

tc_slow_tune_system() {
    if [[ -f /etc/ssh/sshd_config ]]; then
        sed -i '/^#\?MaxStartups/d' /etc/ssh/sshd_config
        sed -i '/^#\?MaxSessions/d' /etc/ssh/sshd_config
        sed -i '/^#\?ClientAliveInterval/d' /etc/ssh/sshd_config
        sed -i '/^#\?ClientAliveCountMax/d' /etc/ssh/sshd_config
        sed -i '/^#\?TCPKeepAlive/d' /etc/ssh/sshd_config
        echo "MaxStartups 100:30:500" >> /etc/ssh/sshd_config
        echo "MaxSessions 100" >> /etc/ssh/sshd_config
        echo "ClientAliveInterval 10" >> /etc/ssh/sshd_config
        echo "ClientAliveCountMax 6" >> /etc/ssh/sshd_config
        echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config
        systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true
    fi

    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    sysctl -w net.core.rmem_max=26214400 >/dev/null 2>&1 || true
    sysctl -w net.core.rmem_default=26214400 >/dev/null 2>&1 || true
    sysctl -w net.core.wmem_max=26214400 >/dev/null 2>&1 || true
    sysctl -w net.core.wmem_default=26214400 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.udp_rmem_min=16384 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.udp_wmem_min=16384 >/dev/null 2>&1 || true
    sysctl -w net.netfilter.nf_conntrack_udp_timeout=120 >/dev/null 2>&1 || true
    sysctl -w net.netfilter.nf_conntrack_udp_timeout_stream=300 >/dev/null 2>&1 || true
    sysctl -p >/dev/null 2>&1 || true

    iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 || \
        iptables -t mangle -I FORWARD 1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 || true
    iptables -t mangle -C OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 || \
        iptables -t mangle -I OUTPUT 1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 || true
}

tc_slow_write_iptables_helper() {
    mkdir -p "$TC_SLOW_DIR"
    cat > "$TC_SLOW_IPTABLES" <<EOF
#!/bin/bash
ACTION="\$1"
PORT="${SLOW_PORT:-$TC_SLOW_PORT_DEFAULT}"
REDIR="${SLOW_REDIRECT:-53}"

clear_rules() {
    iptables -D INPUT -p udp --dport "\$REDIR" -j ACCEPT >/dev/null 2>&1 || true
    iptables -D INPUT -p udp --dport "\$PORT" -j ACCEPT >/dev/null 2>&1 || true
    while iptables -t nat -C PREROUTING -p udp -m udp --dport "\$REDIR" -j REDIRECT --to-ports "\$PORT" >/dev/null 2>&1; do
        iptables -t nat -D PREROUTING -p udp -m udp --dport "\$REDIR" -j REDIRECT --to-ports "\$PORT" >/dev/null 2>&1 || break
    done
    while iptables -t nat -C PREROUTING -p udp --dport "\$REDIR" -j REDIRECT --to-ports "\$PORT" >/dev/null 2>&1; do
        iptables -t nat -D PREROUTING -p udp --dport "\$REDIR" -j REDIRECT --to-ports "\$PORT" >/dev/null 2>&1 || break
    done
}

apply_rules() {
    clear_rules
    iptables -I INPUT 1 -p udp --dport "\$REDIR" -j ACCEPT >/dev/null 2>&1 || true
    iptables -I INPUT 1 -p udp --dport "\$PORT" -j ACCEPT >/dev/null 2>&1 || true
    iptables -t nat -I PREROUTING 1 -p udp -m udp --dport "\$REDIR" -j REDIRECT --to-ports "\$PORT" >/dev/null 2>&1 || true
}

case "\$ACTION" in
    apply) apply_rules ;;
    clear) clear_rules ;;
esac
EOF
    chmod +x "$TC_SLOW_IPTABLES" 2>/dev/null || true
}

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
ExecStart=${TC_SLOW_BIN} -udp :${SLOW_PORT} -privkey-file ${TC_SLOW_KEY} ${SLOW_DOMAIN} 127.0.0.1:${SLOW_TRAFFIC}
ExecStopPost=${TC_SLOW_IPTABLES} clear
Restart=always
RestartSec=3
LimitNOFILE=infinity
StandardOutput=append:${TC_SLOW_LOG}
StandardError=append:${TC_SLOW_LOG}

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1 || true
}

tc_slow_apply_redirect() {
    [[ -x "$TC_SLOW_IPTABLES" ]] && "$TC_SLOW_IPTABLES" apply && return 0
    tc_slow_write_iptables_helper
    "$TC_SLOW_IPTABLES" apply
}

tc_slow_restart() {
    tc_slow_load_conf
    tc_slow_tune_system
    tc_slow_write_service
    tc_slow_apply_redirect
    systemctl enable slowdns >/dev/null 2>&1 || true
    systemctl restart slowdns >/dev/null 2>&1 || true
}

tc_slow_check_connection() {
    tc_slow_load_conf
    tc_line
    printf '%bCOMANDO:%b %b%s -udp :%s -privkey-file %s %s 127.0.0.1:%s%b\n' \
        "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$TC_SLOW_BIN" "$SLOW_PORT" "$TC_SLOW_KEY" "$SLOW_DOMAIN" "$SLOW_TRAFFIC" "$TC_NC"
    if systemctl is-active --quiet slowdns 2>/dev/null; then
        tc_msg_ok "SERVICIO SLOWDNS ACTIVO."
    else
        tc_msg_err "SERVICIO SLOWDNS NO ESTÁ ACTIVO."
        journalctl -u slowdns -n 8 --no-pager 2>/dev/null || true
    fi
    if ss -ulnp 2>/dev/null | grep -q ":${SLOW_PORT} "; then
        tc_msg_ok "PUERTO UDP ${SLOW_PORT} EN ESCUCHA."
    else
        tc_msg_err "PUERTO UDP ${SLOW_PORT} NO APARECE EN ESCUCHA."
    fi
}

# ── Detección dinámica de servicios locales ────────────────────
declare -a TC_SLOW_TARGET_LABELS=()
declare -a TC_SLOW_TARGET_PORTS=()

tc_slow_detect_targets() {
    TC_SLOW_TARGET_LABELS=()
    TC_SLOW_TARGET_PORTS=()

    # OpenSSH
    TC_SLOW_TARGET_LABELS+=("OPENSSH")
    TC_SLOW_TARGET_PORTS+=("22")

    # Dropbear
    if [[ -f /etc/default/dropbear ]]; then
        local db_p
        db_p="$(grep -oE '^DROPBEAR_PORT=[0-9]+' /etc/default/dropbear 2>/dev/null | cut -d'=' -f2 || echo "90")"
        TC_SLOW_TARGET_LABELS+=("DROPBEAR")
        TC_SLOW_TARGET_PORTS+=("$db_p")
    fi

    # Proxy HTTP / SOCKS
    if [[ -f /etc/tunnelcore/proxy/proxy.conf ]]; then
        local prx_p
        prx_p="$(grep -oE '^PROXY_PORT="[0-9]+"' /etc/tunnelcore/proxy/proxy.conf 2>/dev/null | grep -oE '[0-9]+' || echo "80")"
        TC_SLOW_TARGET_LABELS+=("PROXY SOCKS")
        TC_SLOW_TARGET_PORTS+=("$prx_p")
    fi
}

tc_slow_pick_traffic() {
    tc_slow_detect_targets
    local opt i left dots pad

    while true; do
        tc_clear
        tc_title "CONFIGURAR SLOWDNS (REDIRECCION)"
        printf '%bPUERTO SLOWDNS (escucha):%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${SLOW_PORT:-5300}" "$TC_NC"
        tc_line
        printf '%b       ¿A QUÉ PUERTO REDIRIGIR EL TRÁFICO?%b\n' "$TC_YELLOW" "$TC_NC"
        tc_line

        for i in "${!TC_SLOW_TARGET_PORTS[@]}"; do
            left="[$((i + 1))] > ${TC_SLOW_TARGET_LABELS[$i]} "
            pad=$((50 - ${#left} - ${#TC_SLOW_TARGET_PORTS[$i]}))
            [[ "$pad" -lt 2 ]] && pad=2
            dots="$(printf '%*s' "$pad" '' | tr ' ' '.')"
            printf '%b[%s]%b %b> %s%b %b%s%b%b%s%b\n' \
                "$TC_NEON" "$((i + 1))" "$TC_NC" "$TC_WHITE" "${TC_SLOW_TARGET_LABELS[$i]}" "$TC_NC" \
                "$TC_YELLOW" "$dots" "$TC_NC" "$TC_GREEN" "${TC_SLOW_TARGET_PORTS[$i]}" "$TC_NC"
        done

        local manual_idx="$(( ${#TC_SLOW_TARGET_PORTS[@]} + 1 ))"
        left="[${manual_idx}] > INGRESAR PUERTO MANUALMENTE "
        pad=$((50 - ${#left}))
        [[ "$pad" -lt 2 ]] && pad=2
        dots="$(printf '%*s' "$pad" '' | tr ' ' '.')"
        printf '%b[%s]%b %b> INGRESAR PUERTO MANUALMENTE%b %b%s%b\n' \
            "$TC_NEON" "$manual_idx" "$TC_NC" "$TC_WHITE" "$TC_NC" "$TC_YELLOW" "$dots" "$TC_NC"

        tc_line
        tc_opt "0" "$(_t 'cancel')"
        tc_line
        tc_prompt
        read -r opt

        [[ "$opt" = "0" ]] && return 1

        if [[ "$opt" =~ ^[0-9]+$ ]] && [[ "$opt" -ge 1 ]] && [[ "$opt" -le "${#TC_SLOW_TARGET_PORTS[@]}" ]]; then
            SLOW_TRAFFIC="${TC_SLOW_TARGET_PORTS[$((opt - 1))]}"
            return 0
        elif [[ "$opt" == "$manual_idx" ]]; then
            printf '%bIngrese puerto destino local [1-65535]:%b ' "$TC_DARK_GREEN" "$TC_NC"
            read -r cust_p
            if tc_valid_port "$cust_p"; then
                SLOW_TRAFFIC="$cust_p"
                return 0
            else
                tc_msg_err "Puerto no válido."
                sleep 1
            fi
        fi
    done
}

tc_slow_configure() {
    tc_clear
    tc_title "CONFIGURAR SLOWDNS"
    tc_slow_load_conf

    printf '%bPUERTO SLOWDNS [Enter = 5300]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r new_port
    [[ -n "$new_port" ]] && SLOW_PORT="$new_port"

    printf '%bDOMINIO NS:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r new_domain
    [[ -n "$new_domain" ]] && SLOW_DOMAIN="$new_domain"

    if [[ -z "$SLOW_DOMAIN" || "$SLOW_DOMAIN" = "ns.example.com" ]]; then
        tc_msg_err "Debe ingresar un dominio NS real apuntando a la IP de esta VPS."
        tc_pause
        return
    fi

    if ! tc_slow_pick_traffic; then
        return
    fi

    SLOW_REDIRECT="53"
    [[ -x "$TC_SLOW_BIN" ]] || tc_slow_download_bin || { tc_pause; return; }
    [[ -f "$TC_SLOW_KEY" && -f "$TC_SLOW_PUB" ]] || tc_slow_generate_keys || { tc_pause; return; }

    tc_slow_save_conf
    tc_slow_restart
    echo ""
    tc_msg_ok "SLOWDNS configurado correctamente."
    tc_slow_check_connection
    tc_pause
}

tc_slow_show_keys() {
    tc_clear
    tc_title "CLAVES SLOWDNS"
    if [[ -f "$TC_SLOW_PUB" ]]; then
        printf '%bCLAVE PUB:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$(cat "$TC_SLOW_PUB")" "$TC_NC"
    else
        printf '%bNo existe clave pública.%b\n' "$TC_RED" "$TC_NC"
    fi

    if [[ -f "$TC_SLOW_KEY" ]]; then
        printf '%bCLAVE PRIV:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$TC_SLOW_KEY" "$TC_NC"
    else
        printf '%bNo existe clave privada.%b\n' "$TC_RED" "$TC_NC"
    fi
    tc_line
    tc_pause
}

tc_slow_custom_keys() {
    tc_clear
    tc_title "PAR DE CLAVES PERSONALES"
    mkdir -p "$TC_SLOW_DIR"

    printf '%bCLAVE PRIVADA:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r priv
    printf '%bCLAVE PUBLICA:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r pub

    if [[ -z "$priv" || -z "$pub" ]]; then
        tc_msg_err "Datos incompletos."
        tc_pause
        return
    fi

    echo "$priv" > "$TC_SLOW_KEY"
    echo "$pub" > "$TC_SLOW_PUB"
    chmod 600 "$TC_SLOW_KEY"
    chmod 644 "$TC_SLOW_PUB"
    tc_slow_restart
    tc_msg_ok "Claves actualizadas."
    tc_pause
}

tc_slow_change_traffic() {
    tc_slow_load_conf
    tc_slow_pick_traffic || return
    tc_slow_save_conf
    tc_slow_restart
    tc_slow_check_connection
    tc_pause
}

tc_slow_change_domain() {
    tc_slow_load_conf
    printf '%bDOMINIO NS:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r new_dom
    [[ -z "$new_dom" ]] && return
    SLOW_DOMAIN="$new_dom"
    tc_slow_save_conf
    tc_slow_restart
    tc_msg_ok "Dominio NS actualizado a $new_dom."
    tc_pause
}

tc_slow_service_status() {
    tc_clear
    tc_title "ESTADO SLOWDNS"
    systemctl status slowdns --no-pager 2>/dev/null || tc_msg_err "Servicio no instalado."
    tc_pause
}

tc_slow_toggle() {
    if tc_slow_is_running; then
        systemctl stop slowdns >/dev/null 2>&1
        [[ -x "$TC_SLOW_IPTABLES" ]] && "$TC_SLOW_IPTABLES" clear >/dev/null 2>&1 || true
        tc_msg_ok "SlowDNS detenido."
    else
        tc_slow_restart
        tc_msg_ok "SlowDNS iniciado."
    fi
    tc_pause
}

tc_slow_logs_live() {
    tc_clear
    tc_title "LOG SLOWDNS EN TIEMPO REAL (Ctrl+C para salir)"
    journalctl -u slowdns -f 2>/dev/null || tail -f "$TC_SLOW_LOG" 2>/dev/null
}

tc_slow_clean_redirects() {
    local tool="$1" old_rule
    while IFS= read -r old_rule; do
        [[ -z "$old_rule" ]] && continue
        old_rule="${old_rule/-A /-D }"
        # shellcheck disable=SC2086
        "$tool" -t nat $old_rule >/dev/null 2>&1 || true
    done < <("$tool" -t nat -S PREROUTING 2>/dev/null | grep -E -- "-p udp .*--dport ${SLOW_REDIRECT:-53} .* -j REDIRECT")
}

tc_slow_uninstall() {
    tc_clear
    tc_title "DESINSTALAR SLOWDNS"
    tc_slow_load_conf

    if ! tc_confirm "¿Está seguro de desinstalar SlowDNS?"; then
        return
    fi

    systemctl stop slowdns >/dev/null 2>&1 || true
    systemctl disable slowdns >/dev/null 2>&1 || true
    rm -f "$TC_SLOW_SERVICE"
    systemctl daemon-reload >/dev/null 2>&1 || true

    iptables -D INPUT -p udp --dport "${SLOW_REDIRECT:-53}" -j ACCEPT >/dev/null 2>&1 || true
    iptables -D INPUT -p udp --dport "$SLOW_PORT" -j ACCEPT >/dev/null 2>&1 || true
    tc_slow_clean_redirects iptables

    rm -rf "$TC_SLOW_DIR" "$TC_SLOW_LOG" "$TC_SLOW_BIN"
    tc_msg_ok "SlowDNS desinstalado por completo."
    tc_pause
}

tc_slow_summary() {
    tc_slow_load_conf
    printf '%bPORT:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$SLOW_PORT" "$TC_NC"
    printf '%bREDIRECT:%b %b%s > %s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "${SLOW_REDIRECT:-53}" "$SLOW_PORT" "$TC_NC"
    printf '%bTRAFIC PORT:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$SLOW_TRAFFIC" "$TC_NC"
    printf '%bNS DOMAIN:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$SLOW_DOMAIN" "$TC_NC"
    if [[ -f "$TC_SLOW_PUB" ]]; then
        printf '%bCLAVE PUB:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$(cat "$TC_SLOW_PUB")" "$TC_NC"
    else
        printf '%bCLAVE PUB:%b %bN/A%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$TC_NC"
    fi
}

tc_slow_config_menu() {
    while true; do
        tc_clear
        tc_title "CONFIGURACION SLOWDNS"
        tc_opt "1" "MIS CLAVES SLOWDNS"
        tc_opt "2" "GENERAR NUEVO PAR DE CLAVES"
        tc_opt "3" "PAR DE CLAVES PERSONALES"
        tc_opt "4" "MODIFICAR PUERTO DE TRAFICO"
        tc_opt "5" "MODIFICAR DOMINIO NS"
        tc_line
        tc_opt "0" "$(_t 'back')"
        tc_line
        tc_prompt
        read -r cfg_opt
        case "$cfg_opt" in
            1|01) tc_slow_show_keys ;;
            2|02)
                tc_slow_generate_keys && tc_slow_restart && tc_msg_ok "Nuevo par de claves generado." && tc_pause
                ;;
            3|03) tc_slow_custom_keys ;;
            4|04) tc_slow_change_traffic ;;
            5|05) tc_slow_change_domain ;;
            0|00) break ;;
            *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
        esac
    done
}

tc_slow_menu() {
    while true; do
        tc_clear
        if [[ ! -f "$TC_SLOW_CONF" ]]; then
            tc_title "SLOWDNS"
            tc_opt "1" "INSTALAR SLOWDNS"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_slow_configure ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        else
            tc_title "SLOWDNS"
            tc_slow_summary
            tc_line
            tc_opt "1" "CONFIGURACION DE SLOWDNS"
            tc_opt "2" "ESTADO DEL SERVICIO"
            tc_opt "3" "REINICIAR SERVICIO"
            tc_opt "4" "INICIAR/PARAR SERVICIO" "  $(tc_slow_status_mark)"
            tc_opt "5" "VERIFICAR CONEXION / ESTADO"
            tc_opt "6" "LOG SLOWDNS EN TIEMPO REAL"
            tc_opt "7" "REINSTALAR"
            tc_opt "8" "DESINSTALAR SLOWDNS"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_slow_config_menu ;;
                2|02) tc_slow_service_status ;;
                3|03)
                    tc_slow_restart
                    tc_msg_ok "Servicio reiniciado."
                    tc_pause
                    ;;
                4|04) tc_slow_toggle ;;
                5|05)
                    tc_clear
                    tc_title "VERIFICAR SLOWDNS"
                    tc_slow_check_connection
                    tc_pause
                    ;;
                6|06) tc_slow_logs_live ;;
                7|07)
                    tc_slow_download_bin && tc_slow_configure
                    ;;
                8|08) tc_slow_uninstall ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        fi
    done
}
