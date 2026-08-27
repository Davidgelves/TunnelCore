#!/bin/bash
# TunnelCore - modules/checkusers.sh
# Instalador/control del CheckUser original de ADMRufu/Rufus.

TC_RUFU_CHECKUSER_URL="https://gitlab.com/rufu99/admrufu2.0/-/raw/main/sbin/checkuser"
TC_RUFU_CHECKUSER_DIR="/root/ADMRufu/checkuser"
TC_RUFU_CHECKUSER_BIN="${TC_RUFU_CHECKUSER_DIR}/checkuser"
TC_RUFU_CHECKUSER_LOG="${TC_RUFU_CHECKUSER_DIR}/checkuser.log"
TC_RUFU_CHECKUSER_CONF="${TC_RUFU_CHECKUSER_DIR}/checkuser.conf"
TC_RUFU_CHECKUSER_SERVICE_FILE="/etc/systemd/system/checkuser.service"
TC_RUFU_CHECKUSER_SERVICE="checkuser"
TC_OLD_CHECK_SERVICE="/etc/systemd/system/tunnelcore-checkuser.service"
TC_OLD_CHECK_DIR="/etc/tunnelcore/checkuser"

tc_checkuser_is_installed() {
    [[ -x "$TC_RUFU_CHECKUSER_BIN" && -f "$TC_RUFU_CHECKUSER_SERVICE_FILE" ]]
}

tc_checkuser_is_running() {
    systemctl is-active --quiet "$TC_RUFU_CHECKUSER_SERVICE" 2>/dev/null
}

tc_checkuser_status_mark() {
    if tc_checkuser_is_running; then
        printf '%bo%b' "$TC_GREEN" "$TC_NC"
    else
        printf '%bx%b' "$TC_RED" "$TC_NC"
    fi
}

tc_checkuser_stop_old_tunnelcore_api() {
    systemctl stop tunnelcore-checkuser >/dev/null 2>&1 || true
    systemctl disable tunnelcore-checkuser >/dev/null 2>&1 || true
    rm -f "$TC_OLD_CHECK_SERVICE" 2>/dev/null || true
    rm -rf "$TC_OLD_CHECK_DIR" 2>/dev/null || true
    systemctl daemon-reload >/dev/null 2>&1 || true
}

tc_checkuser_vps_timezone() {
    local zone
    zone="$(timedatectl show -p Timezone --value 2>/dev/null)"
    [[ -z "$zone" && -f /etc/timezone ]] && zone="$(cat /etc/timezone 2>/dev/null)"
    echo "${zone:-$(date +%Z 2>/dev/null || echo Local)}"
}

tc_checkuser_conf_get() {
    local key="$1" default="$2" value=""
    if [[ -f "$TC_RUFU_CHECKUSER_CONF" ]]; then
        value="$(grep -E "^${key}=" "$TC_RUFU_CHECKUSER_CONF" 2>/dev/null | tail -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//')"
    fi
    echo "${value:-$default}"
}

tc_checkuser_current_port() {
    tc_checkuser_conf_get "PORT" "5454"
}

tc_checkuser_current_timezone() {
    tc_checkuser_conf_get "TIMEZONE" "$(tc_checkuser_vps_timezone)"
}

tc_checkuser_current_format() {
    tc_checkuser_conf_get "DATE_FORMAT" "DDMMYY"
}

tc_checkuser_download_rufu() {
    mkdir -p "$TC_RUFU_CHECKUSER_DIR"
    tc_download "$TC_RUFU_CHECKUSER_URL" "$TC_RUFU_CHECKUSER_BIN" 3 || return 1
    chmod +x "$TC_RUFU_CHECKUSER_BIN"
}

tc_checkuser_write_conf() {
    local port="$1" timezone="$2" date_format="$3"
    mkdir -p "$TC_RUFU_CHECKUSER_DIR"
    cat > "$TC_RUFU_CHECKUSER_CONF" <<EOF
PORT="${port}"
TIMEZONE="${timezone}"
DATE_FORMAT="${date_format}"
EOF
}

tc_checkuser_write_service() {
    local port="$1" timezone="$2"
    mkdir -p "$TC_RUFU_CHECKUSER_DIR"
    cat > "$TC_RUFU_CHECKUSER_SERVICE_FILE" <<EOF
[Unit]
Description=CheckUser by @Rufu99
After=network.target

[Service]
User=root
WorkingDirectory=${TC_RUFU_CHECKUSER_DIR}
Environment=TZ=${timezone}
ExecStart=${TC_RUFU_CHECKUSER_BIN} --port ${port}
StandardOutput=append:${TC_RUFU_CHECKUSER_LOG}
StandardError=append:${TC_RUFU_CHECKUSER_LOG}
Restart=always
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF
}

tc_checkuser_prepare_binary() {
    tc_checkuser_stop_old_tunnelcore_api

    if [[ "$(uname -m)" != "x86_64" && "$(uname -m)" != "amd64" ]]; then
        tc_msg_warn "El CheckUser de Rufus es binario x86_64; esta arquitectura puede no ser compatible."
        sleep 2
    fi

    if [[ ! -x "$TC_RUFU_CHECKUSER_BIN" ]]; then
        printf '%bDescargando CheckUser original de Rufus...%b\n' "$TC_YELLOW" "$TC_NC"
        printf '%b%s%b\n' "$TC_WHITE" "$TC_RUFU_CHECKUSER_URL" "$TC_NC"
        tc_checkuser_download_rufu || return 1
    fi
}

tc_checkuser_select_timezone() {
    local vps_zone opt
    vps_zone="$(tc_checkuser_vps_timezone)"
    while true; do
        tc_clear
        tc_title "CONFIGURACION DE CHECKUSER - ONLINE"
        tc_opt "1" "UTC (HORA INTERNACIONAL)"
        tc_opt "2" "ZONA HORARIA (${vps_zone})"
        tc_opt "0" "VOLVER"
        tc_line
        tc_prompt
        read -r opt
        case "$opt" in
            1|01) TC_CHECKUSER_SELECTED_TIMEZONE="UTC"; return 0 ;;
            2|02) TC_CHECKUSER_SELECTED_TIMEZONE="$vps_zone"; return 0 ;;
            0|00) return 1 ;;
            *) tc_msg_err "Opcion no valida."; sleep 1 ;;
        esac
    done
}

tc_checkuser_select_date_format() {
    local port="$1" timezone="$2" opt
    while true; do
        tc_clear
        tc_title "CONFIGURACION DE CHECKUSER - ONLINE"
        printf '%bPUERTO:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$port" "$TC_NC"
        printf '%bZONA HORARIA:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$timezone" "$TC_NC"
        printf '%b------------------------------------------------------------%b\n' "$TC_WHITE" "$TC_NC"
        printf '%bFORMATO DE FECHA...%b\n' "$TC_YELLOW" "$TC_NC"
        tc_opt "1" "DDMMYY"
        tc_opt "2" "(01-02-1996)"
        tc_line
        printf '%bFORMATO:%b ' "$TC_CYAN" "$TC_NC"
        read -r opt
        case "$opt" in
            1|01) TC_CHECKUSER_SELECTED_DATE_FORMAT="DDMMYY"; return 0 ;;
            2|02) TC_CHECKUSER_SELECTED_DATE_FORMAT="DD-MM-YYYY"; return 0 ;;
            *) tc_msg_err "Opcion no valida."; sleep 1 ;;
        esac
    done
}

tc_checkuser_apply_screen() {
    local port="$1" timezone="$2" date_format="$3" opt
    while true; do
        tc_clear
        tc_title "CONFIGURACION DE CHECKUSER - ONLINE"
        printf '%bPUERTO:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$port" "$TC_NC"
        printf '%bZONA HORARIA:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$timezone" "$TC_NC"
        printf '%bFORMATO DE FECHA:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$date_format" "$TC_NC"
        printf '%b------------------------%b\n' "$TC_WHITE" "$TC_NC"
        tc_opt "1" "APLICAR"
        tc_opt "2" "CANCELAR"
        tc_line
        tc_prompt
        read -r opt
        case "$opt" in
            1|01) return 0 ;;
            2|02|0|00) return 1 ;;
            *) tc_msg_err "Opcion no valida."; sleep 1 ;;
        esac
    done
}

tc_checkuser_install_wizard() {
    local port timezone date_format
    tc_checkuser_stop_old_tunnelcore_api
    tc_clear
    tc_title "CHECKUSER - ONLINE"
    printf '%bINGRESA PUERTO [ENTER: 5454]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r port
    [[ -z "$port" ]] && port="5454"

    if ! tc_valid_port "$port"; then
        tc_msg_err "Puerto no valido."
        tc_pause
        return
    fi
    if tc_port_in_use "$port" && ! tc_checkuser_is_running; then
        tc_msg_err "El puerto $port ya esta siendo usado por otro servicio."
        tc_pause
        return
    fi

    tc_checkuser_select_timezone || return
    timezone="$TC_CHECKUSER_SELECTED_TIMEZONE"
    tc_checkuser_select_date_format "$port" "$timezone" || return
    date_format="$TC_CHECKUSER_SELECTED_DATE_FORMAT"
    tc_checkuser_apply_screen "$port" "$timezone" "$date_format" || return

    tc_clear
    tc_title "CONFIGURACION DE CHECKUSER - ONLINE"
    printf '%bPUERTO:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$port" "$TC_NC"
    printf '%bZONA HORARIA:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$timezone" "$TC_NC"
    printf '%bFORMATO DE FECHA:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$date_format" "$TC_NC"
    printf '%b------------------------%b\n' "$TC_WHITE" "$TC_NC"

    if ! tc_checkuser_prepare_binary; then
        tc_msg_err "No se pudo descargar el CheckUser de Rufus."
        tc_pause
        return
    fi
    tc_checkuser_write_conf "$port" "$timezone" "$date_format"
    tc_checkuser_write_service "$port" "$timezone"

    systemctl daemon-reload >/dev/null 2>&1 && printf '       systemctl daemon-reload............%bOK%b\n' "$TC_GREEN" "$TC_NC" || printf '       systemctl daemon-reload............%bERROR%b\n' "$TC_RED" "$TC_NC"
    systemctl enable "$TC_RUFU_CHECKUSER_SERVICE" >/dev/null 2>&1 || true
    systemctl restart "$TC_RUFU_CHECKUSER_SERVICE" >/dev/null 2>&1 && printf '       systemctl start checkuser..........%bOK%b\n' "$TC_GREEN" "$TC_NC" || printf '       systemctl start checkuser..........%bERROR%b\n' "$TC_RED" "$TC_NC"

    tc_line
    printf '%b>>>> ENTER PARA CONTINUAR <<<<<%b' "$TC_YELLOW" "$TC_NC"
    read -r _
}

tc_checkuser_uninstall() {
    systemctl stop "$TC_RUFU_CHECKUSER_SERVICE" >/dev/null 2>&1 || true
    systemctl disable "$TC_RUFU_CHECKUSER_SERVICE" >/dev/null 2>&1 || true
    rm -f "$TC_RUFU_CHECKUSER_SERVICE_FILE" 2>/dev/null || true
    rm -rf "$TC_RUFU_CHECKUSER_DIR" 2>/dev/null || true
    systemctl daemon-reload >/dev/null 2>&1 || true
}

tc_checkuser_installed_menu() {
    local ip port opt
    while true; do
        tc_clear
        ip="$(tc_public_ip)"
        port="$(tc_checkuser_current_port)"
        tc_title "CHECKUSER - ONLINE"
        printf '%bURL CHECKUSER:%b %bhttp://%s:%s/checkuser%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$ip" "$port" "$TC_NC"
        printf '%bURL ONLINES:  %b %bhttp://%s:%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$ip" "$port" "$TC_NC"
        printf '%b-------------------------------------------------------------------------%b\n' "$TC_WHITE" "$TC_NC"
        tc_opt "1" "ESTADO DE SERVICIO"
        tc_opt "2" "REINICIAR SERVICIO"
        tc_opt "3" "INICIAR/PARAR CHECKUSER" " $(tc_checkuser_status_mark)"
        tc_opt "4" "LOG CHECKUSER"
        tc_opt "5" "DESINSTALAR"
        tc_opt "0" "VOLVER"
        tc_line
        tc_prompt
        read -r opt

        case "$opt" in
            1|01)
                tc_clear
                tc_title "ESTADO DEL SERVICIO"
                systemctl status "$TC_RUFU_CHECKUSER_SERVICE" --no-pager 2>/dev/null || tc_msg_warn "CheckUser no esta instalado."
                tc_pause
                ;;
            2|02)
                systemctl restart "$TC_RUFU_CHECKUSER_SERVICE" >/dev/null 2>&1
                tc_msg_ok "CheckUser reiniciado."
                tc_pause
                ;;
            3|03)
                if tc_checkuser_is_running; then
                    systemctl stop "$TC_RUFU_CHECKUSER_SERVICE" >/dev/null 2>&1
                    tc_msg_ok "CheckUser detenido."
                else
                    systemctl start "$TC_RUFU_CHECKUSER_SERVICE" >/dev/null 2>&1
                    tc_msg_ok "CheckUser iniciado."
                fi
                tc_pause
                ;;
            4|04)
                tc_clear
                tc_title "LOG CHECKUSER"
                if [[ -f "$TC_RUFU_CHECKUSER_LOG" ]]; then
                    tail -n 100 "$TC_RUFU_CHECKUSER_LOG"
                else
                    tc_msg_warn "No hay log disponible."
                fi
                tc_pause
                ;;
            5|05)
                printf '%bConfirma que quiere desinstalar CheckUser? [S/N]:%b ' "$TC_YELLOW" "$TC_NC"
                read -r confirm
                if [[ "$confirm" =~ ^[sS]$ ]]; then
                    tc_checkuser_uninstall
                    tc_msg_ok "CheckUser desinstalado."
                    tc_pause
                    return
                fi
                tc_msg_warn "Operacion cancelada."
                tc_pause
                ;;
            0|00) return ;;
            *) tc_msg_err "Opcion no valida."; sleep 1 ;;
        esac
    done
}

tc_checkuser_menu() {
    local opt
    while true; do
        if tc_checkuser_is_installed; then
            tc_checkuser_installed_menu
            return
        fi

        tc_clear
        tc_title "CHECKUSER - ONLINE"
        tc_opt "1" "INSTALAR CHECKUSER"
        tc_opt "0" "VOLVER"
        tc_line
        tc_prompt
        read -r opt
        case "$opt" in
            1|01) tc_checkuser_install_wizard ;;
            0|00) return ;;
            *) tc_msg_err "Opcion no valida."; sleep 1 ;;
        esac
    done
}
