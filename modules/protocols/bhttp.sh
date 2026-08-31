#!/bin/bash
# TunnelCore - Gestion de BTUN / HCR

TC_BHTTP_DIR="/etc/tunnelcore/bhttp"
TC_BHTTP_BTUN_CONF="${TC_BHTTP_DIR}/btun.conf"
TC_BHTTP_HCR_CONF="${TC_BHTTP_DIR}/hcr.conf"
TC_BHTTP_BTUN_BIN="/usr/local/lib/tunnelcore-bilola-server"
TC_BHTTP_HCR_BIN="/usr/local/lib/tunnelcore-hcr-server"
TC_BHTTP_ASSET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin"
TC_BHTTP_BTUN_SERVICE="/etc/systemd/system/tunnelcore-btun.service"
TC_BHTTP_HCR_SERVICE="/etc/systemd/system/tunnelcore-hcr.service"
TC_BHTTP_STUNNEL_CONF="/etc/stunnel/stunnel.conf"

TC_BHTTP_SELECTED_TARGET="127.0.0.1:22"

tc_bhttp_service_name() {
    case "$1" in
        btun) echo "tunnelcore-btun" ;;
        hcr) echo "tunnelcore-hcr" ;;
    esac
}

tc_bhttp_label() {
    case "$1" in
        btun) echo "BTUN (BHTTP)" ;;
        hcr) echo "HCR Relay" ;;
    esac
}

tc_bhttp_conf_path() {
    case "$1" in
        btun) echo "$TC_BHTTP_BTUN_CONF" ;;
        hcr) echo "$TC_BHTTP_HCR_CONF" ;;
    esac
}

tc_bhttp_bin_path() {
    case "$1" in
        btun) echo "$TC_BHTTP_BTUN_BIN" ;;
        hcr) echo "$TC_BHTTP_HCR_BIN" ;;
    esac
}

tc_bhttp_service_path() {
    case "$1" in
        btun) echo "$TC_BHTTP_BTUN_SERVICE" ;;
        hcr) echo "$TC_BHTTP_HCR_SERVICE" ;;
    esac
}

tc_bhttp_load_conf() {
    local proto="$1" conf
    BHTTP_PORT="8080"
    BHTTP_TARGET="127.0.0.1:22"
    BHTTP_TLS="0"
    BHTTP_TLS_PORT=""
    BHTTP_TLS_DOMAIN=""
    BHTTP_TLS_CERT=""
    BHTTP_TLS_KEY=""
    BHTTP_TLS_MODE=""
    BHTTP_TLS_INTERNAL_PORT=""
    BHTTP_PLAIN_PORT=""
    conf="$(tc_bhttp_conf_path "$proto")"
    if [[ -f "$conf" ]]; then
        # shellcheck disable=SC1090
        . "$conf"
    fi
}

tc_bhttp_save_conf() {
    local proto="$1" conf
    conf="$(tc_bhttp_conf_path "$proto")"
    mkdir -p "$TC_BHTTP_DIR"
cat > "$conf" <<EOF
BHTTP_PORT="${BHTTP_PORT:-8080}"
BHTTP_TARGET="${BHTTP_TARGET:-127.0.0.1:22}"
BHTTP_TLS="${BHTTP_TLS:-0}"
BHTTP_TLS_PORT="${BHTTP_TLS_PORT:-}"
BHTTP_TLS_DOMAIN="${BHTTP_TLS_DOMAIN:-}"
BHTTP_TLS_CERT="${BHTTP_TLS_CERT:-}"
BHTTP_TLS_KEY="${BHTTP_TLS_KEY:-}"
BHTTP_TLS_MODE="${BHTTP_TLS_MODE:-}"
BHTTP_TLS_INTERNAL_PORT="${BHTTP_TLS_INTERNAL_PORT:-}"
BHTTP_PLAIN_PORT="${BHTTP_PLAIN_PORT:-}"
EOF
}

tc_bhttp_is_running() {
    local proto="$1" service
    service="$(tc_bhttp_service_name "$proto")"
    systemctl is-active --quiet "$service" 2>/dev/null
}

tc_bhttp_status_mark() {
    if tc_bhttp_is_running "$1"; then
        printf '%bo%b' "$TC_GREEN" "$TC_NC"
    else
        printf '%bx%b' "$TC_RED" "$TC_NC"
    fi
}

tc_bhttp_status_summary() {
    local btun hcr
    btun="$(tc_bhttp_status_mark btun 2>/dev/null || echo x)"
    hcr="$(tc_bhttp_status_mark hcr 2>/dev/null || echo x)"
    printf '%s/%s' "$btun" "$hcr"
}

tc_bhttp_get_dropbear_port() {
    if declare -f tc_dropbear_get_port >/dev/null 2>&1; then
        tc_dropbear_get_port
    elif [[ -f /etc/default/dropbear ]]; then
        grep -oE '^DROPBEAR_PORT=[0-9]+' /etc/default/dropbear 2>/dev/null | cut -d'=' -f2 || echo "90"
    else
        echo "90"
    fi
}

tc_bhttp_ask_target() {
    local listen_p="${1:-8080}" dropbear_p manual_p
    dropbear_p="$(tc_bhttp_get_dropbear_port)"

    while true; do
        tc_clear
        tc_title "REDIRECCIONAR TRAFICO"
        printf '%bPUERTO DE ESCUCHA:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$listen_p" "$TC_NC"
        tc_line
        printf '%b       A QUE PUERTO LOCAL DESEA REDIRIGIR?%b\n' "$TC_YELLOW" "$TC_NC"
        tc_line
        printf '%b[1]%b %b> SSH (OpenSSH) ....................%b %b22%b\n' "$TC_NEON" "$TC_NC" "$TC_WHITE" "$TC_NC" "$TC_GREEN" "$TC_NC"
        printf '%b[2]%b %b> Dropbear SSH .....................%b %b%s%b\n' "$TC_NEON" "$TC_NC" "$TC_WHITE" "$TC_NC" "$TC_GREEN" "$dropbear_p" "$TC_NC"
        printf '%b[3]%b %b> INGRESAR PUERTO MANUALMENTE%b\n' "$TC_NEON" "$TC_NC" "$TC_WHITE" "$TC_NC"
        tc_line
        tc_opt "0" "$(_t 'cancel')"
        tc_line
        tc_prompt
        read -r ch

        case "$ch" in
            1|01) TC_BHTTP_SELECTED_TARGET="127.0.0.1:22"; return 0 ;;
            2|02) TC_BHTTP_SELECTED_TARGET="127.0.0.1:${dropbear_p}"; return 0 ;;
            3|03)
                printf '%bIngrese puerto destino local [1-65535]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                read -r manual_p
                if tc_valid_port "$manual_p"; then
                    TC_BHTTP_SELECTED_TARGET="127.0.0.1:${manual_p}"
                    return 0
                fi
                tc_msg_err "Puerto no valido."
                sleep 1
                ;;
            0|00) return 1 ;;
            *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
        esac
    done
}

tc_bhttp_install_binary() {
    local proto="$1" bin asset local_asset
    bin="$(tc_bhttp_bin_path "$proto")"
    [[ -x "$bin" ]] && return 0

    case "$proto" in
        btun) asset="bilola-server" ;;
        hcr) asset="hcr-server" ;;
        *) return 1 ;;
    esac

    local_asset="${TC_BHTTP_ASSET_DIR}/${asset}"
    if [[ -f "$local_asset" ]]; then
        tc_msg_ok "Instalando binario local ${asset}..."
        cp -f "$local_asset" "$bin"
        chmod +x "$bin"
        [[ -x "$bin" ]] && return 0
    fi

    tc_msg_err "Binario local ${asset} no encontrado en ${TC_BHTTP_ASSET_DIR}."
    return 1
}

tc_bhttp_tls_mark() {
    if [[ "${BHTTP_TLS:-0}" = "1" ]]; then
        printf 'ACTIVADO'
    else
        printf 'DESACTIVADO'
    fi
}

tc_bhttp_tcp_listening() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "(^|:)${port}$"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tln 2>/dev/null | awk '{print $4}' | grep -qE "(^|:)${port}$"
    else
        return 1
    fi
}

tc_bhttp_supports_native_tls() {
    local proto="$1" bin help
    bin="$(tc_bhttp_bin_path "$proto")"
    [[ -x "$bin" ]] || tc_bhttp_install_binary "$proto" || return 1
    help="$("$bin" --help 2>&1 || true)"

    case "$proto" in
        btun)
            grep -qiE -- '--tls-cert|tls-cert' <<< "$help" && grep -qiE -- '--tls-key|tls-key' <<< "$help"
            ;;
        hcr)
            grep -qiE -- '--tls-cert|tls-cert' <<< "$help" &&
            grep -qiE -- '--tls-key|tls-key' <<< "$help" &&
            grep -qiE -- 'transport.*tls|--transport' <<< "$help"
            ;;
        *) return 1 ;;
    esac
}

tc_bhttp_tls_section() {
    case "$1" in
        btun) echo "tunnelcore-btun-tls" ;;
        hcr) echo "tunnelcore-hcr-tls" ;;
    esac
}

tc_bhttp_remove_stunnel_section() {
    local proto="$1" section tmp
    section="$(tc_bhttp_tls_section "$proto")"
    [[ -f "$TC_BHTTP_STUNNEL_CONF" ]] || return 0
    tmp="/tmp/tunnelcore-stunnel-${proto}-$$.conf"
    awk -v section="$section" '
        /^\[/ {
            current=$0
            gsub(/^\[/, "", current)
            gsub(/\]$/, "", current)
            skip=(current == section)
        }
        !skip { print }
    ' "$TC_BHTTP_STUNNEL_CONF" > "$tmp" && mv "$tmp" "$TC_BHTTP_STUNNEL_CONF"
}

tc_bhttp_init_stunnel_conf() {
    mkdir -p /etc/stunnel
    if [[ ! -f "$TC_BHTTP_STUNNEL_CONF" ]]; then
        cat > "$TC_BHTTP_STUNNEL_CONF" <<EOF
client = no
pid = /var/run/stunnel4.pid

EOF
    fi
}

tc_bhttp_write_stunnel_section() {
    local proto="$1" tls_port="$2" internal_port="$3" cert="$4" key="$5" section
    section="$(tc_bhttp_tls_section "$proto")"

    tc_apt_install stunnel4 openssl
    tc_bhttp_init_stunnel_conf
    tc_bhttp_remove_stunnel_section "$proto"

    cat >> "$TC_BHTTP_STUNNEL_CONF" <<EOF

[${section}]
accept = ${tls_port}
connect = 127.0.0.1:${internal_port}
cert = ${cert}
key = ${key}
EOF

    if [[ -f /etc/default/stunnel4 ]]; then
        sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || true
    fi

    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable stunnel4 >/dev/null 2>&1 || true
    systemctl restart stunnel4 >/dev/null 2>&1 || service stunnel4 restart >/dev/null 2>&1 || true
}

tc_bhttp_domain_resolves_here() {
    local domain="$1" public_ip resolved
    public_ip="$(tc_public_ip)"
    resolved="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1; exit}')"
    [[ -z "$resolved" ]] && resolved="$(dig +short A "$domain" 2>/dev/null | head -n1)"
    [[ -z "$resolved" ]] && resolved="$(host "$domain" 2>/dev/null | awk '/has address/ {print $4; exit}')"
    [[ -n "$resolved" && "$resolved" = "$public_ip" ]]
}

tc_bhttp_default_cert() {
    local domain="$1"
    BHTTP_TLS_CERT="/etc/letsencrypt/live/${domain}/fullchain.pem"
    BHTTP_TLS_KEY="/etc/letsencrypt/live/${domain}/privkey.pem"
}

tc_bhttp_ensure_cert() {
    local domain="$1" cert key email
    tc_bhttp_default_cert "$domain"
    cert="$BHTTP_TLS_CERT"
    key="$BHTTP_TLS_KEY"

    if [[ -s "$cert" && -s "$key" ]]; then
        return 0
    fi

    tc_msg_warn "No se encontro certificado Let's Encrypt para ${domain}."
    if ! tc_confirm "Desea instalar/usar Certbot para emitirlo?"; then
        return 1
    fi

    printf '%bEmail para Let'\''s Encrypt [Enter = admin@%s]:%b ' "$TC_DARK_GREEN" "$domain" "$TC_NC"
    read -r email
    [[ -z "$email" ]] && email="admin@${domain}"

    tc_apt_install certbot
    certbot certonly --standalone --non-interactive --agree-tos \
        --email "$email" -d "$domain" >/dev/null 2>&1 || {
        tc_msg_err "Certbot no pudo emitir el certificado. Revise DNS, puerto 80 y firewall."
        return 1
    }

    [[ -s "$cert" && -s "$key" ]]
}

tc_bhttp_tls_internal_port() {
    local port="$1"
    if [[ -n "${BHTTP_TLS_INTERNAL_PORT:-}" ]] && tc_valid_port "$BHTTP_TLS_INTERNAL_PORT"; then
        echo "$BHTTP_TLS_INTERNAL_PORT"
    else
        echo $((port + 10000 <= 65535 ? port + 10000 : port - 10000))
    fi
}

tc_bhttp_find_free_internal_port() {
    local base="$1" candidate i
    candidate="$(tc_bhttp_tls_internal_port "$base")"
    for ((i = 0; i < 200; i++)); do
        if tc_valid_port "$candidate" && ! tc_port_in_use "$candidate"; then
            echo "$candidate"
            return 0
        fi
        candidate=$((candidate + 1))
        (( candidate > 65535 )) && candidate="18080"
    done
    return 1
}

tc_bhttp_display_port() {
    if [[ "${BHTTP_TLS:-0}" = "1" && -n "${BHTTP_TLS_PORT:-}" ]]; then
        echo "$BHTTP_TLS_PORT"
    else
        echo "${BHTTP_PORT:-8080}"
    fi
}

tc_bhttp_restart_current() {
    local proto="$1" service_name
    service_name="$(tc_bhttp_service_name "$proto")"

    if [[ "${BHTTP_TLS:-0}" = "1" && "${BHTTP_TLS_MODE:-}" = "stunnel" ]]; then
        BHTTP_TLS_INTERNAL_PORT="${BHTTP_TLS_INTERNAL_PORT:-$(tc_bhttp_tls_internal_port "${BHTTP_TLS_PORT:-443}")}"
        tc_bhttp_write_service "$proto" "${BHTTP_TLS_INTERNAL_PORT:-$(tc_bhttp_tls_internal_port "${BHTTP_TLS_PORT:-443}")}" "${BHTTP_TARGET:-127.0.0.1:22}" || return 1
        systemctl restart "$service_name" >/dev/null 2>&1 || return 1
        tc_bhttp_write_stunnel_section "$proto" "${BHTTP_TLS_PORT:-443}" "${BHTTP_TLS_INTERNAL_PORT}" "$BHTTP_TLS_CERT" "$BHTTP_TLS_KEY" || return 1
    else
        tc_bhttp_write_service "$proto" "${BHTTP_PORT:-8080}" "${BHTTP_TARGET:-127.0.0.1:22}" || return 1
        systemctl restart "$service_name" >/dev/null 2>&1 || return 1
    fi
}

tc_bhttp_enable_tls() {
    local proto="$1" label tls_port domain cert key old_port old_tls old_tls_port old_domain old_cert old_key old_mode old_internal old_plain mode internal_port
    label="$(tc_bhttp_label "$proto")"
    tc_bhttp_load_conf "$proto"

    if ! tc_bhttp_is_running "$proto"; then
        tc_msg_err "Primero debe activar ${label}."
        tc_pause
        return
    fi

    old_port="$BHTTP_PORT"
    old_tls="$BHTTP_TLS"
    old_tls_port="$BHTTP_TLS_PORT"
    old_domain="$BHTTP_TLS_DOMAIN"
    old_cert="$BHTTP_TLS_CERT"
    old_key="$BHTTP_TLS_KEY"
    old_mode="$BHTTP_TLS_MODE"
    old_internal="$BHTTP_TLS_INTERNAL_PORT"
    old_plain="$BHTTP_PLAIN_PORT"

    printf '%bPuerto TLS publico [Enter = 443]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r tls_port
    [[ -z "$tls_port" ]] && tls_port="443"
    if ! tc_valid_port "$tls_port"; then
        tc_msg_err "Puerto TLS no valido."
        tc_pause
        return
    fi
    if tc_port_in_use "$tls_port"; then
        tc_msg_err "El puerto TLS $tls_port ya esta en uso."
        tc_pause
        return
    fi

    printf '%bDominio para TLS:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r domain
    if [[ -z "$domain" ]]; then
        tc_msg_err "Debe ingresar un dominio."
        tc_pause
        return
    fi

    if ! tc_bhttp_domain_resolves_here "$domain"; then
        tc_msg_err "El dominio no resuelve hacia la IP publica de esta VPS."
        tc_pause
        return
    fi

    if ! tc_bhttp_ensure_cert "$domain"; then
        BHTTP_PORT="$old_port"; BHTTP_TLS="$old_tls"; BHTTP_TLS_PORT="$old_tls_port"; BHTTP_TLS_DOMAIN="$old_domain"
        BHTTP_TLS_CERT="$old_cert"; BHTTP_TLS_KEY="$old_key"; BHTTP_TLS_MODE="$old_mode"; BHTTP_TLS_INTERNAL_PORT="$old_internal"
        BHTTP_PLAIN_PORT="$old_plain"
        tc_bhttp_save_conf "$proto"
        tc_pause
        return
    fi
    cert="$BHTTP_TLS_CERT"
    key="$BHTTP_TLS_KEY"

    mode="stunnel"
    if tc_bhttp_supports_native_tls "$proto"; then
        mode="native"
    fi

    if [[ "$mode" = "native" ]]; then
        BHTTP_PORT="$tls_port"
        BHTTP_TLS_INTERNAL_PORT=""
    else
        internal_port="$(tc_bhttp_find_free_internal_port "$tls_port")" || {
            tc_msg_err "No se encontro un puerto interno libre para ${label}."
            BHTTP_PORT="$old_port"; BHTTP_TLS="$old_tls"; BHTTP_TLS_PORT="$old_tls_port"; BHTTP_TLS_DOMAIN="$old_domain"
            BHTTP_TLS_CERT="$old_cert"; BHTTP_TLS_KEY="$old_key"; BHTTP_TLS_MODE="$old_mode"; BHTTP_TLS_INTERNAL_PORT="$old_internal"
            BHTTP_PLAIN_PORT="$old_plain"
            tc_bhttp_save_conf "$proto"
            tc_pause
            return
        }
        BHTTP_PORT="$internal_port"
        BHTTP_TLS_INTERNAL_PORT="$internal_port"
    fi

    BHTTP_TLS="1"
    BHTTP_TLS_PORT="$tls_port"
    BHTTP_TLS_DOMAIN="$domain"
    BHTTP_TLS_CERT="$cert"
    BHTTP_TLS_KEY="$key"
    BHTTP_TLS_MODE="$mode"
    BHTTP_PLAIN_PORT="${old_plain:-$old_port}"
    tc_bhttp_save_conf "$proto"

    if tc_bhttp_restart_current "$proto" && tc_bhttp_tcp_listening "$tls_port"; then
        if [[ "$mode" = "stunnel" ]]; then
            tc_msg_ok "${label} TLS activo en puerto $tls_port via Stunnel."
        else
            tc_msg_ok "${label} TLS nativo activo en puerto $tls_port."
        fi
    else
        BHTTP_PORT="$old_port"; BHTTP_TLS="$old_tls"; BHTTP_TLS_PORT="$old_tls_port"; BHTTP_TLS_DOMAIN="$old_domain"
        BHTTP_TLS_CERT="$old_cert"; BHTTP_TLS_KEY="$old_key"; BHTTP_TLS_MODE="$old_mode"; BHTTP_TLS_INTERNAL_PORT="$old_internal"
        BHTTP_PLAIN_PORT="$old_plain"
        tc_bhttp_save_conf "$proto"
        tc_bhttp_restart_current "$proto" >/dev/null 2>&1 || true
        tc_msg_err "No se pudo activar TLS. Se restauro la configuracion anterior."
    fi
    tc_pause
}

tc_bhttp_disable_tls() {
    local proto="$1" label old_tls old_tls_port old_domain old_cert old_key old_mode old_internal old_plain plain_port
    label="$(tc_bhttp_label "$proto")"
    tc_bhttp_load_conf "$proto"

    if [[ "${BHTTP_TLS:-0}" != "1" ]]; then
        tc_msg_warn "TLS ya esta desactivado."
        tc_pause
        return
    fi

    old_tls="$BHTTP_TLS"; old_tls_port="$BHTTP_TLS_PORT"; old_domain="$BHTTP_TLS_DOMAIN"
    old_cert="$BHTTP_TLS_CERT"; old_key="$BHTTP_TLS_KEY"; old_mode="$BHTTP_TLS_MODE"; old_internal="$BHTTP_TLS_INTERNAL_PORT"
    old_plain="$BHTTP_PLAIN_PORT"
    plain_port="${BHTTP_PLAIN_PORT:-8080}"

    if [[ "${BHTTP_TLS_MODE:-}" = "stunnel" ]]; then
        tc_bhttp_remove_stunnel_section "$proto"
        systemctl restart stunnel4 >/dev/null 2>&1 || service stunnel4 restart >/dev/null 2>&1 || true
    fi

    BHTTP_TLS="0"
    BHTTP_TLS_PORT=""
    BHTTP_TLS_DOMAIN=""
    BHTTP_TLS_CERT=""
    BHTTP_TLS_KEY=""
    BHTTP_TLS_MODE=""
    BHTTP_TLS_INTERNAL_PORT=""
    BHTTP_PLAIN_PORT=""
    BHTTP_PORT="$plain_port"
    tc_bhttp_save_conf "$proto"

    if tc_bhttp_restart_current "$proto"; then
        tc_msg_ok "TLS desactivado para ${label}. Servicio normal restaurado en puerto ${BHTTP_PORT}."
    else
        BHTTP_TLS="$old_tls"; BHTTP_TLS_PORT="$old_tls_port"; BHTTP_TLS_DOMAIN="$old_domain"
        BHTTP_TLS_CERT="$old_cert"; BHTTP_TLS_KEY="$old_key"; BHTTP_TLS_MODE="$old_mode"; BHTTP_TLS_INTERNAL_PORT="$old_internal"
        BHTTP_PLAIN_PORT="$old_plain"
        tc_bhttp_save_conf "$proto"
        tc_msg_err "No se pudo desactivar TLS correctamente. Se conservo la configuracion previa."
    fi
    tc_pause
}

tc_bhttp_write_service() {
    local proto="$1" port="$2" target="$3"
    local service_path service_name bin target_host target_port description extra_args listen_host listen_port
    service_path="$(tc_bhttp_service_path "$proto")"
    service_name="$(tc_bhttp_service_name "$proto")"
    bin="$(tc_bhttp_bin_path "$proto")"
    target_host="${target%:*}"
    target_port="${target##*:}"
    listen_host="0.0.0.0"
    listen_port="$port"

    if [[ "${BHTTP_TLS:-0}" = "1" && "${BHTTP_TLS_MODE:-}" = "stunnel" ]]; then
        listen_host="127.0.0.1"
        listen_port="${BHTTP_TLS_INTERNAL_PORT:-$(tc_bhttp_tls_internal_port "$port")}"
    fi

    case "$proto" in
        btun)
            description="TunnelCore BTUN BHTTP Server"
            extra_args="--listen ${listen_host}:${listen_port} --target ${target_host}:${target_port}"
            if [[ "${BHTTP_TLS:-0}" = "1" && "${BHTTP_TLS_MODE:-}" = "native" ]]; then
                extra_args="${extra_args} --tls-cert ${BHTTP_TLS_CERT} --tls-key ${BHTTP_TLS_KEY}"
            fi
            ;;
        hcr)
            description="TunnelCore HCR Relay"
            extra_args="--listen ${listen_host}:${listen_port} --target ${target_host}:${target_port} --transport plain --max-download-frame 6144 --download-poll-timeout 8s"
            if [[ "${BHTTP_TLS:-0}" = "1" && "${BHTTP_TLS_MODE:-}" = "native" ]]; then
                extra_args="--listen ${listen_host}:${listen_port} --target ${target_host}:${target_port} --transport tls --tls-cert ${BHTTP_TLS_CERT} --tls-key ${BHTTP_TLS_KEY} --max-download-frame 6144 --download-poll-timeout 8s"
            fi
            ;;
        *) return 1 ;;
    esac

    cat > "$service_path" <<EOF
[Unit]
Description=${description}
After=network-online.target ssh.service sshd.service dropbear.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=${bin} ${extra_args}
Restart=on-failure
RestartSec=3
User=root
LimitNOFILE=65536
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable "$service_name" >/dev/null 2>&1
}

tc_bhttp_start() {
    local proto="$1" port="$2" target="$3" service_name
    service_name="$(tc_bhttp_service_name "$proto")"

    tc_bhttp_install_binary "$proto" || return 1
    BHTTP_PORT="$port"
    BHTTP_TARGET="$target"
    tc_bhttp_save_conf "$proto"
    tc_bhttp_write_service "$proto" "$port" "$target" || return 1
    systemctl restart "$service_name" >/dev/null 2>&1
}

tc_bhttp_stop() {
    local proto="$1" service_name service_path bin
    service_name="$(tc_bhttp_service_name "$proto")"
    service_path="$(tc_bhttp_service_path "$proto")"
    bin="$(tc_bhttp_bin_path "$proto")"

    tc_bhttp_load_conf "$proto"
    if [[ "${BHTTP_TLS:-0}" = "1" && "${BHTTP_TLS_MODE:-}" = "stunnel" ]]; then
        tc_bhttp_remove_stunnel_section "$proto"
        systemctl restart stunnel4 >/dev/null 2>&1 || service stunnel4 restart >/dev/null 2>&1 || true
    fi

    systemctl stop "$service_name" >/dev/null 2>&1 || true
    systemctl disable "$service_name" >/dev/null 2>&1 || true
    rm -f "$service_path"
    systemctl daemon-reload >/dev/null 2>&1 || true
    rm -f "$bin"
}

tc_bhttp_configure() {
    local proto="$1" label port
    label="$(tc_bhttp_label "$proto")"
    tc_clear
    tc_title "CONFIGURAR ${label}"

    printf '%bPuerto de escucha [Enter = 8080]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r port
    [[ -z "$port" ]] && port="8080"

    if ! tc_valid_port "$port"; then
        tc_msg_err "Puerto no valido."
        tc_pause
        return
    fi

    if tc_port_in_use "$port"; then
        tc_msg_warn "El puerto $port ya esta en uso."
        if ! tc_confirm "Desea continuar de todos modos?"; then
            return
        fi
    fi

    if ! tc_bhttp_ask_target "$port"; then
        return
    fi

    tc_bhttp_start "$proto" "$port" "$TC_BHTTP_SELECTED_TARGET"
    if tc_bhttp_is_running "$proto"; then
        tc_msg_ok "${label} activo en puerto $port redirigiendo a $TC_BHTTP_SELECTED_TARGET."
    else
        tc_msg_err "Error al iniciar ${label}."
    fi
    tc_pause
}

tc_bhttp_service_status() {
    local proto="$1" service_name label
    service_name="$(tc_bhttp_service_name "$proto")"
    label="$(tc_bhttp_label "$proto")"
    tc_clear
    tc_title "ESTADO ${label}"
    systemctl status "$service_name" --no-pager -l 2>/dev/null || tc_msg_err "Servicio no instalado."
    tc_pause
}

tc_bhttp_show_logs() {
    local proto="$1" service_name label
    service_name="$(tc_bhttp_service_name "$proto")"
    label="$(tc_bhttp_label "$proto")"
    tc_clear
    tc_title "LOG ${label}"
    journalctl -u "$service_name" -n 40 --no-pager 2>/dev/null || tc_msg_err "Servicio no instalado."
    tc_pause
}

tc_bhttp_follow_logs() {
    local proto="$1" service_name label
    service_name="$(tc_bhttp_service_name "$proto")"
    label="$(tc_bhttp_label "$proto")"
    tc_clear
    tc_title "LOG EN VIVO ${label} (Ctrl+C para salir)"
    journalctl -u "$service_name" -f --no-pager
}

tc_bhttp_protocol_menu() {
    local proto="$1" label opt new_p display_port
    label="$(tc_bhttp_label "$proto")"

    while true; do
        tc_clear
        tc_bhttp_load_conf "$proto"
        tc_title "${label} $(tc_bhttp_status_mark "$proto")"

        if tc_bhttp_is_running "$proto"; then
            display_port="$(tc_bhttp_display_port)"
            printf '%bPUERTO:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$display_port" "$TC_NC"
            printf '%bDESTINO:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "${BHTTP_TARGET:-127.0.0.1:22}" "$TC_NC"
            printf '%bTLS:%b %b%s%b' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$(tc_bhttp_tls_mark)" "$TC_NC"
            if [[ "${BHTTP_TLS:-0}" = "1" ]]; then
                printf '  %bMODO:%b %b%s%b' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${BHTTP_TLS_MODE:-N/A}" "$TC_NC"
            fi
            printf '\n'
            tc_line
            tc_opt "1" "DESACTIVAR ${label}"
            if [[ "${BHTTP_TLS:-0}" = "1" ]]; then
                tc_opt "2" "DESACTIVAR TLS"
            else
                tc_opt "2" "ACTIVAR TLS"
            fi
            tc_opt "3" "CAMBIAR PUERTO"
            tc_opt "4" "REDIRIGIR DESTINO (SSH / DROPBEAR / MANUAL)"
            tc_opt "5" "REINICIAR"
            tc_opt "6" "ESTADO"
            tc_opt "7" "VER LOG"
            tc_opt "8" "LOG EN VIVO"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt

            case "$opt" in
                1|01) tc_bhttp_stop "$proto"; tc_msg_ok "${label} desactivado."; tc_pause ;;
                2|02)
                    if [[ "${BHTTP_TLS:-0}" = "1" ]]; then
                        tc_bhttp_disable_tls "$proto"
                    else
                        tc_bhttp_enable_tls "$proto"
                    fi
                    ;;
                3|03)
                    printf '%bNuevo puerto [Enter = %s]:%b ' "$TC_DARK_GREEN" "$display_port" "$TC_NC"
                    read -r new_p
                    [[ -z "$new_p" ]] && new_p="$display_port"
                    if tc_valid_port "$new_p"; then
                        if [[ "${BHTTP_TLS:-0}" = "1" ]]; then
                            if tc_port_in_use "$new_p"; then
                                tc_msg_err "El puerto $new_p ya esta en uso."
                            else
                                BHTTP_TLS_PORT="$new_p"
                                if [[ "${BHTTP_TLS_MODE:-}" = "native" ]]; then
                                    BHTTP_PORT="$new_p"
                                fi
                                tc_bhttp_save_conf "$proto"
                                tc_bhttp_restart_current "$proto"
                                tc_msg_ok "Puerto TLS actualizado a $new_p."
                            fi
                        else
                            tc_bhttp_start "$proto" "$new_p" "${BHTTP_TARGET:-127.0.0.1:22}"
                            tc_msg_ok "Puerto actualizado a $new_p."
                        fi
                    else
                        tc_msg_err "Puerto no valido."
                    fi
                    tc_pause
                    ;;
                4|04)
                    if tc_bhttp_ask_target "$display_port"; then
                        BHTTP_TARGET="$TC_BHTTP_SELECTED_TARGET"
                        tc_bhttp_save_conf "$proto"
                        tc_bhttp_restart_current "$proto"
                        tc_msg_ok "Destino actualizado a $TC_BHTTP_SELECTED_TARGET."
                        tc_pause
                    fi
                    ;;
                5|05) tc_bhttp_restart_current "$proto" >/dev/null 2>&1; tc_msg_ok "Servicio reiniciado."; tc_pause ;;
                6|06) tc_bhttp_service_status "$proto" ;;
                7|07) tc_bhttp_show_logs "$proto" ;;
                8|08) tc_bhttp_follow_logs "$proto" ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        else
            tc_opt "1" "ACTIVAR ${label}"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_bhttp_configure "$proto" ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        fi
    done
}

tc_bhttp_menu() {
    while true; do
        tc_clear
        tc_title "BTUN / HCR"
        tc_opt "1" "BTUN (BHTTP)" "  $(tc_bhttp_status_mark btun)"
        tc_opt "2" "HCR RELAY" "  $(tc_bhttp_status_mark hcr)"
        tc_line
        tc_opt "0" "$(_t 'back')"
        tc_line
        tc_prompt
        read -r opt

        case "$opt" in
            1|01) tc_bhttp_protocol_menu btun ;;
            2|02) tc_bhttp_protocol_menu hcr ;;
            0|00) break ;;
            *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
        esac
    done
}
