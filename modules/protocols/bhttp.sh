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
TC_BHTTP_RAW_BASE="${TC_BHTTP_RAW_BASE:-https://gitlab.com/rufu99/admrufu2.0/-/raw/main/bin}"

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
    local proto="$1" bin url asset local_asset
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

    tc_msg_warn "Binario local ${asset} no encontrado; intentando descarga de respaldo..."
    url="${TC_BHTTP_RAW_BASE}/${asset}"
    if ! tc_download "$url" "$bin" 3; then
        tc_msg_err "No se pudo descargar ${asset}."
        return 1
    fi
    chmod +x "$bin"
    [[ -x "$bin" ]]
}

tc_bhttp_write_service() {
    local proto="$1" port="$2" target="$3"
    local service_path service_name bin target_host target_port description extra_args
    service_path="$(tc_bhttp_service_path "$proto")"
    service_name="$(tc_bhttp_service_name "$proto")"
    bin="$(tc_bhttp_bin_path "$proto")"
    target_host="${target%:*}"
    target_port="${target##*:}"

    case "$proto" in
        btun)
            description="TunnelCore BTUN BHTTP Server"
            extra_args="--listen 0.0.0.0:${port} --target ${target_host}:${target_port}"
            ;;
        hcr)
            description="TunnelCore HCR Relay"
            extra_args="--listen :${port} --target ${target_host}:${target_port} --transport plain --max-download-frame 6144 --download-poll-timeout 8s"
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
    local proto="$1" label opt new_p
    label="$(tc_bhttp_label "$proto")"

    while true; do
        tc_clear
        tc_bhttp_load_conf "$proto"
        tc_title "${label} $(tc_bhttp_status_mark "$proto")"

        if tc_bhttp_is_running "$proto"; then
            printf '%bPUERTO:%b %b%s%b  %bDESTINO:%b %b%s%b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "${BHTTP_PORT:-8080}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "${BHTTP_TARGET:-127.0.0.1:22}" "$TC_NC"
            tc_line
            tc_opt "1" "DESACTIVAR ${label}"
            tc_opt "2" "CAMBIAR PUERTO DE ESCUCHA"
            tc_opt "3" "REDIRIGIR DESTINO (SSH / DROPBEAR / MANUAL)"
            tc_opt "4" "REINICIAR SERVICIO"
            tc_opt "5" "ESTADO DEL SERVICIO"
            tc_opt "6" "VER LOG"
            tc_opt "7" "LOG EN VIVO"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt

            case "$opt" in
                1|01) tc_bhttp_stop "$proto"; tc_msg_ok "${label} desactivado."; tc_pause ;;
                2|02)
                    printf '%bNuevo puerto de escucha [Enter = %s]:%b ' "$TC_DARK_GREEN" "${BHTTP_PORT:-8080}" "$TC_NC"
                    read -r new_p
                    [[ -z "$new_p" ]] && new_p="${BHTTP_PORT:-8080}"
                    if tc_valid_port "$new_p"; then
                        tc_bhttp_start "$proto" "$new_p" "${BHTTP_TARGET:-127.0.0.1:22}"
                        tc_msg_ok "Puerto actualizado a $new_p."
                    else
                        tc_msg_err "Puerto no valido."
                    fi
                    tc_pause
                    ;;
                3|03)
                    if tc_bhttp_ask_target "${BHTTP_PORT:-8080}"; then
                        tc_bhttp_start "$proto" "${BHTTP_PORT:-8080}" "$TC_BHTTP_SELECTED_TARGET"
                        tc_msg_ok "Destino actualizado a $TC_BHTTP_SELECTED_TARGET."
                        tc_pause
                    fi
                    ;;
                4|04) systemctl restart "$(tc_bhttp_service_name "$proto")" >/dev/null 2>&1; tc_msg_ok "Servicio reiniciado."; tc_pause ;;
                5|05) tc_bhttp_service_status "$proto" ;;
                6|06) tc_bhttp_show_logs "$proto" ;;
                7|07) tc_bhttp_follow_logs "$proto" ;;
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
