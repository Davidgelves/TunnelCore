#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/badvpn.sh
#  Gestión de BadVPN UDPGW (UDP Gateway)
#  Compila desde fuente oficial de ambrop72/badvpn o instala binario
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════

TC_BADVPN_BIN="/usr/local/bin/badvpn-udpgw"
TC_BADVPN_DIR="/etc/tunnelcore/badvpn"
TC_BADVPN_CONF="${TC_BADVPN_DIR}/badvpn.conf"
TC_BADVPN_SERVICE="/etc/systemd/system/tunnelcore-badvpn.service"

tc_badvpn_is_installed() {
    [[ -x "$TC_BADVPN_BIN" || -x "/bin/badvpn-udpgw" ]]
}

tc_badvpn_is_running() {
    systemctl is-active --quiet tunnelcore-badvpn 2>/dev/null || pgrep -f 'badvpn-udpgw' >/dev/null 2>&1
}

tc_badvpn_status_mark() {
    if tc_badvpn_is_running; then
        printf '%bo%b' "$TC_GREEN" "$TC_NC"
    else
        printf '%bx%b' "$TC_RED" "$TC_NC"
    fi
}

tc_badvpn_load_conf() {
    BADVPN_PORT="7300"
    if [[ -f "$TC_BADVPN_CONF" ]]; then
        # shellcheck disable=SC1090
        . "$TC_BADVPN_CONF"
    fi
}

tc_badvpn_save_conf() {
    mkdir -p "$TC_BADVPN_DIR"
    cat > "$TC_BADVPN_CONF" <<EOF
BADVPN_PORT="${BADVPN_PORT:-7300}"
EOF
}

tc_badvpn_install_bin() {
    if [[ -x "$TC_BADVPN_BIN" ]]; then
        return 0
    fi
    if [[ -x "/bin/badvpn-udpgw" ]]; then
        ln -sf "/bin/badvpn-udpgw" "$TC_BADVPN_BIN"
        return 0
    fi

    tc_msg_ok "Compilando badvpn-udpgw desde la fuente oficial..."
    tc_apt_install ca-certificates curl build-essential cmake make gcc g++

    local version="1.999.130"
    local workdir="/tmp/badvpn-build-$$"
    mkdir -p "$workdir"

    local url="https://github.com/ambrop72/badvpn/archive/refs/tags/${version}.tar.gz"
    if ! tc_download "$url" "${workdir}/badvpn.tar.gz" 3; then
        tc_msg_err "No se pudo descargar la fuente de BadVPN."
        rm -rf "$workdir"
        return 1
    fi

    tar -xzf "${workdir}/badvpn.tar.gz" -C "$workdir"
    mkdir -p "${workdir}/build"
    (
        cd "${workdir}/build"
        cmake "../badvpn-${version}" -DCMAKE_INSTALL_PREFIX=/usr/local -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
        make -j"$(nproc 2>/dev/null || echo 1)"
        make install
    ) >/dev/null 2>&1 || {
        tc_msg_err "Error al compilar BadVPN."
        rm -rf "$workdir"
        return 1
    }

    rm -rf "$workdir"
    [[ -x "$TC_BADVPN_BIN" ]]
}

tc_badvpn_start() {
    local port="$1"
    mkdir -p "$TC_BADVPN_DIR"

    tc_badvpn_install_bin || {
        tc_msg_err "No se pudo instalar BadVPN."
        return 1
    }

    BADVPN_PORT="$port"
    tc_badvpn_save_conf

    cat > "$TC_BADVPN_SERVICE" <<EOF
[Unit]
Description=TunnelCore BadVPN UDP Gateway
After=network.target

[Service]
Type=simple
ExecStart=${TC_BADVPN_BIN} --listen-addr 127.0.0.1:${port} --max-clients 10000 --max-connections-for-client 8 --client-socket-sndbuf 10000
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable tunnelcore-badvpn >/dev/null 2>&1
    systemctl restart tunnelcore-badvpn >/dev/null 2>&1
}

tc_badvpn_stop() {
    systemctl stop tunnelcore-badvpn >/dev/null 2>&1 || true
    systemctl disable tunnelcore-badvpn >/dev/null 2>&1 || true
    pkill -f 'badvpn-udpgw' >/dev/null 2>&1 || true
}

tc_badvpn_menu() {
    while true; do
        tc_clear
        tc_badvpn_load_conf
        tc_title "GESTIÓN BADVPN (UDP GATEWAY) $(tc_badvpn_status_mark)"

        if ! tc_badvpn_is_running; then
            tc_opt "1" "ACTIVAR BADVPN (Puerto 7300)"
            tc_opt "2" "ACTIVAR BADVPN EN PUERTO PERSONALIZADO"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01)
                    tc_badvpn_start "7300"
                    if tc_badvpn_is_running; then
                        tc_msg_ok "BadVPN activo en puerto 7300."
                    else
                        tc_msg_err "Error al iniciar BadVPN."
                    fi
                    tc_pause
                    ;;
                2|02)
                    printf '%bPuerto de escucha UDPGW [1-65535]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r port
                    if tc_valid_port "$port"; then
                        tc_badvpn_start "$port"
                        if tc_badvpn_is_running; then
                            tc_msg_ok "BadVPN activo en puerto $port."
                        else
                            tc_msg_err "Error al iniciar BadVPN."
                        fi
                    else
                        tc_msg_err "Puerto no válido."
                    fi
                    tc_pause
                    ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        else
            printf '%bPUERTO BADVPN:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "${BADVPN_PORT:-7300}" "$TC_NC"
            tc_line
            tc_opt "1" "DESACTIVAR BADVPN"
            tc_opt "2" "CAMBIAR PUERTO"
            tc_opt "3" "REINICIAR SERVICIO"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01)
                    tc_badvpn_stop
                    tc_msg_ok "BadVPN detenido."
                    tc_pause
                    ;;
                2|02)
                    printf '%bNuevo puerto [1-65535]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r port
                    if tc_valid_port "$port"; then
                        tc_badvpn_start "$port"
                        tc_msg_ok "Puerto actualizado a $port."
                    else
                        tc_msg_err "Puerto no válido."
                    fi
                    tc_pause
                    ;;
                3|03)
                    systemctl restart tunnelcore-badvpn >/dev/null 2>&1
                    tc_msg_ok "BadVPN reiniciado."
                    tc_pause
                    ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        fi
    done
}
