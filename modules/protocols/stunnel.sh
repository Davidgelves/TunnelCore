#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/stunnel.sh
#  Gestión Avanzada de Stunnel4 (Multi-puerto SSL con redirección)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════

TC_STUNNEL_CONF="/etc/stunnel/stunnel.conf"
TC_STUNNEL_CERT="/etc/stunnel/stunnel.pem"

tc_stunnel_is_installed() {
    command -v stunnel4 >/dev/null 2>&1 || command -v stunnel >/dev/null 2>&1
}

tc_stunnel_is_running() {
    systemctl is-active --quiet stunnel4 2>/dev/null || systemctl is-active --quiet stunnel 2>/dev/null || pgrep -x stunnel4 >/dev/null 2>&1
}

tc_stunnel_status_mark() {
    if tc_stunnel_is_running; then
        printf '%bo%b' "$TC_GREEN" "$TC_NC"
    else
        printf '%bx%b' "$TC_RED" "$TC_NC"
    fi
}

tc_stunnel_has_ports() {
    [[ -f "$TC_STUNNEL_CONF" ]] && grep -qE "^[[:space:]]*accept[[:space:]]*=" "$TC_STUNNEL_CONF" 2>/dev/null
}

tc_stunnel_conf_value() {
    local file="$1" key="$2" default="$3" value
    value="$(grep -oE "^${key}=\"?[0-9]+\"?" "$file" 2>/dev/null | head -n1 | sed -E 's/^[^=]+=//;s/"//g')"
    echo "${value:-$default}"
}

tc_stunnel_dropbear_port() {
    tc_stunnel_conf_value "/etc/default/dropbear" "DROPBEAR_PORT" "90"
}

tc_stunnel_tcp_listening() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "(^|:)${port}$"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tln 2>/dev/null | awk '{print $4}' | grep -qE "(^|:)${port}$"
    else
        return 1
    fi
}

tc_stunnel_port_owner() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -ltnp 2>/dev/null | awk -v port="$port" '$4 ~ "(^|:)" port "$" {print; found=1} END {exit found ? 0 : 1}'
    elif command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null
    else
        return 1
    fi
}

tc_stunnel_diag() {
    local port
    tc_line
    printf '%bDiagnostico Stunnel:%b\n' "$TC_YELLOW" "$TC_NC"
    if [[ -f "$TC_STUNNEL_CONF" ]]; then
        while read -r port; do
            [[ -z "$port" ]] && continue
            printf '%bPuerto configurado:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$port" "$TC_NC"
            if tc_stunnel_port_owner "$port"; then
                tc_stunnel_port_owner "$port"
            else
                printf '%bEstado puerto:%b %bLIBRE%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$TC_NC"
            fi
        done < <(awk -F= '/^[[:space:]]*accept[[:space:]]*=/{gsub(/[ \t]/,"",$2); if($2!="") print $2}' "$TC_STUNNEL_CONF" | sort -u)
    fi
    tc_line
    printf '%bEstado stunnel4:%b\n' "$TC_YELLOW" "$TC_NC"
    systemctl status stunnel4 --no-pager -l 2>/dev/null | tail -n 20 || service stunnel4 status 2>/dev/null | tail -n 20 || true
    if command -v journalctl >/dev/null 2>&1; then
        tc_line
        printf '%bUltimas lineas stunnel4:%b\n' "$TC_YELLOW" "$TC_NC"
        journalctl -u stunnel4 --no-pager -n 20 2>/dev/null || true
    fi
}

tc_stunnel_add_target_option() {
    local label="$1" port="$2"
    [[ -z "$port" || ! "$port" =~ ^[0-9]+$ ]] && return 0
    tc_stunnel_tcp_listening "$port" || return 0
    TC_STUNNEL_TARGET_LABELS+=("$label")
    TC_STUNNEL_TARGET_PORTS+=("$port")
}

tc_stunnel_load_targets() {
    local dropbear_p proxy_p proxy_p2 ws_p ssh_ports ssh_port
    TC_STUNNEL_TARGET_LABELS=()
    TC_STUNNEL_TARGET_PORTS=()

    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null || pgrep -x sshd >/dev/null 2>&1; then
        ssh_ports="$(grep -hE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -n -u)"
        [[ -z "$ssh_ports" ]] && ssh_ports="22"
        while read -r ssh_port; do
            [[ -z "$ssh_port" ]] && continue
            tc_stunnel_add_target_option "SSH (OpenSSH)" "$ssh_port"
        done <<< "$ssh_ports"
    fi

    if systemctl is-active --quiet dropbear 2>/dev/null || pgrep -x dropbear >/dev/null 2>&1; then
        dropbear_p="$(tc_stunnel_dropbear_port)"
        tc_stunnel_add_target_option "Dropbear SSH" "$dropbear_p"
    fi

    if systemctl is-active --quiet tunnelcore-proxy 2>/dev/null; then
        proxy_p="$(tc_stunnel_conf_value "/etc/tunnelcore/proxy/proxy.conf" "PROXY_PORT" "")"
        proxy_p2="$(tc_stunnel_conf_value "/etc/tunnelcore/proxy/proxy.conf" "PROXY_PORT2" "")"
        tc_stunnel_add_target_option "Proxy HTTP/SOCKS" "$proxy_p"
        tc_stunnel_add_target_option "Proxy HTTP/SOCKS 2" "$proxy_p2"
    fi

    if systemctl is-active --quiet tunnelcore-ws 2>/dev/null; then
        ws_p="$(tc_stunnel_conf_value "/etc/tunnelcore/websocket/websocket.conf" "WS_PORT" "")"
        tc_stunnel_add_target_option "WebSocket SSH" "$ws_p"
    fi
}

TC_STUNNEL_TARGET="127.0.0.1:22"

tc_stunnel_ask_target() {
    local listen_p="${1:-443}"
    local manual_p idx label port dots pad_width

    while true; do
        tc_stunnel_load_targets
        tc_clear
        tc_title "CONFIGURAR STUNNEL (REDIRECCION)"
        printf '%bPUERTO SSL (escucha):%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$listen_p" "$TC_NC"
        tc_line
        printf '%b       A QUE PUERTO LOCAL REDIRIGIR EL TRAFICO?%b\n' "$TC_YELLOW" "$TC_NC"
        tc_line
        if [[ ${#TC_STUNNEL_TARGET_PORTS[@]} -eq 0 ]]; then
            tc_msg_warn "No hay puertos compatibles activos detectados."
        else
            for idx in "${!TC_STUNNEL_TARGET_PORTS[@]}"; do
                label="${TC_STUNNEL_TARGET_LABELS[$idx]}"
                port="${TC_STUNNEL_TARGET_PORTS[$idx]}"
                dots=".............................."
                pad_width=$((30 - ${#label}))
                (( pad_width < 1 )) && pad_width=1
                printf '%b[%d]%b %b> %s %.*s%b %b%s%b\n' "$TC_NEON" "$((idx + 1))" "$TC_NC" "$TC_WHITE" "$label" "$pad_width" "$dots" "$TC_NC" "$TC_GREEN" "$port" "$TC_NC"
            done
        fi
        printf '%b[%d]%b %b> INGRESAR PUERTO MANUALMENTE%b\n' "$TC_NEON" "$((${#TC_STUNNEL_TARGET_PORTS[@]} + 1))" "$TC_NC" "$TC_WHITE" "$TC_NC"
        tc_line
        tc_opt "0" "$(_t 'cancel')"
        tc_line

        tc_prompt
        read -r ch

        [[ "$ch" == "0" || "$ch" == "00" ]] && return 1
        if [[ "$ch" =~ ^0*[0-9]+$ ]]; then
            ch="$((10#$ch))"
            if (( ch >= 1 && ch <= ${#TC_STUNNEL_TARGET_PORTS[@]} )); then
                TC_STUNNEL_TARGET="127.0.0.1:${TC_STUNNEL_TARGET_PORTS[$((ch - 1))]}"
                return 0
            elif (( ch == ${#TC_STUNNEL_TARGET_PORTS[@]} + 1 )); then
                printf '%bIngrese puerto destino local [1-65535]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                read -r manual_p
                if tc_valid_port "$manual_p"; then
                    TC_STUNNEL_TARGET="127.0.0.1:${manual_p}"
                    return 0
                fi
                tc_msg_err "Puerto invalido."
                sleep 1
                continue
            fi
        fi
        tc_msg_err "$(_t 'invalid_option')"
        sleep 1
    done
}

tc_stunnel_gen_cert() {
    mkdir -p /etc/stunnel
    if [[ ! -f "$TC_STUNNEL_CERT" ]]; then
        openssl req -new -x509 -days 3650 -nodes \
            -subj "/C=US/ST=State/L=City/O=TunnelCore/OU=VPN/CN=*" \
            -out "$TC_STUNNEL_CERT" -keyout "$TC_STUNNEL_CERT" >/dev/null 2>&1
        chmod 600 "$TC_STUNNEL_CERT"
    fi
}

tc_stunnel_init_base_conf() {
    mkdir -p /etc/stunnel
    tc_stunnel_gen_cert
    if [[ ! -f "$TC_STUNNEL_CONF" ]]; then
        cat > "$TC_STUNNEL_CONF" <<EOF
cert = ${TC_STUNNEL_CERT}
client = no
pid = /var/run/stunnel4.pid

EOF
    fi
}

# ── Listar puertos SSL activos en stunnel.conf ────────────────
tc_stunnel_list_active_ports() {
    if [[ ! -f "$TC_STUNNEL_CONF" ]]; then
        printf '  %bNo hay puertos SSL configurados.%b\n' "$TC_YELLOW" "$TC_NC"
        return
    fi

    local count=0
    local cur_section="" cur_accept="" cur_connect=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(echo "$line" | sed 's/^[ \t]*//;s/[ \t]*$//')"
        if [[ "$line" =~ ^\[(.*)\]$ ]]; then
            if [[ -n "$cur_accept" && -n "$cur_connect" ]]; then
                printf '  %b• Puerto SSL %b%-5s%b -> Redirige a %b%-18s%b [%s]\n' \
                    "$TC_GREEN" "$TC_WHITE" "$cur_accept" "$TC_NC" \
                    "$TC_CYAN" "$cur_connect" "$TC_NC" "$cur_section"
                ((count++))
            fi
            cur_section="${BASH_REMATCH[1]}"
            cur_accept=""
            cur_connect=""
        elif [[ "$line" =~ ^accept[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            cur_accept="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^connect[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            cur_connect="${BASH_REMATCH[1]}"
        fi
    done < "$TC_STUNNEL_CONF"

    if [[ -n "$cur_accept" && -n "$cur_connect" ]]; then
        printf '  %b• Puerto SSL %b%-5s%b -> Redirige a %b%-18s%b [%s]\n' \
            "$TC_GREEN" "$TC_WHITE" "$cur_accept" "$TC_NC" \
            "$TC_CYAN" "$cur_connect" "$TC_NC" "$cur_section"
        ((count++))
    fi

    if (( count == 0 )); then
        printf '  %bNo hay puertos SSL configurados.%b\n' "$TC_YELLOW" "$TC_NC"
    fi
}

# ── 1. AGREGAR PUERTO SSL Y REDIRECCIÓN ───────────────────────
tc_stunnel_add_port() {
    tc_clear
    tc_title "AGREGAR PUERTO SSL / TLS (STUNNEL)"

    tc_stunnel_init_base_conf
    tc_apt_install stunnel4 openssl

    local port target
    while true; do
        printf '%bPuerto de escucha SSL [ej: 443, 444, 8443]:%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r port
        [[ -z "$port" ]] && port="443"

        if ! tc_valid_port "$port"; then
            tc_msg_err "Puerto inválido. Ingrese un número entre 1 y 65535."
            continue
        fi

        if grep -qE "^[[:space:]]*accept[[:space:]]*=[[:space:]]*${port}[[:space:]]*$" "$TC_STUNNEL_CONF" 2>/dev/null; then
            tc_msg_err "El puerto $port ya está configurado en Stunnel."
            continue
        fi
        if tc_port_in_use "$port"; then
            tc_msg_err "El puerto $port ya esta siendo usado por otro servicio. Elija otro puerto o libere ese puerto."
            continue
        fi

        tc_msg_ok "Puerto $port disponible."
        break
    done

    if ! tc_stunnel_ask_target "$port"; then
        return
    fi
    target="$TC_STUNNEL_TARGET"

    local tag="ssl-${port}"
    cat >> "$TC_STUNNEL_CONF" <<EOF

[${tag}]
accept = ${port}
connect = ${target}
EOF

    # Habilitar en /etc/default/stunnel4
    if [[ -f /etc/default/stunnel4 ]]; then
        sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || true
    fi

    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable stunnel4 >/dev/null 2>&1 || true
    systemctl restart stunnel4 >/dev/null 2>&1 || service stunnel4 restart >/dev/null 2>&1 || true

    if tc_stunnel_is_running; then
        tc_msg_ok "Puerto SSL $port configurado y activo redirigiendo a $target."
    else
        tc_msg_warn "Puerto agregado. Si no inició, verifique que el puerto $port no esté ocupado por otro servicio."
    fi
    tc_pause
}

# ── 2. ELIMINAR PUERTO SSL ────────────────────────────────────
tc_stunnel_del_port() {
    tc_clear
    tc_title "ELIMINAR PUERTO SSL (STUNNEL)"

    if [[ ! -f "$TC_STUNNEL_CONF" ]]; then
        tc_msg_warn "No existe configuración de Stunnel."
        tc_pause
        return
    fi

    local ports=()
    mapfile -t ports < <(awk -F= '/^[[:space:]]*accept[[:space:]]*=/{gsub(/[ \t]/,"",$2); if($2!="") print $2}' "$TC_STUNNEL_CONF" | sort -u)

    if [[ ${#ports[@]} -eq 0 ]]; then
        tc_msg_warn "No hay puertos SSL para eliminar."
        tc_pause
        return
    fi

    local idx=1
    printf '%b%-4s %s%b\n' "$TC_YELLOW" "NUM" "PUERTO SSL" "$TC_NC"
    tc_line
    for p in "${ports[@]}"; do
        printf '%b[%d]%b > %bPuerto %s%b\n' "$TC_RED" "$idx" "$TC_NC" "$TC_WHITE" "$p" "$TC_NC"
        ((idx++))
    done

    tc_line
    tc_opt "0" "$(_t 'cancel')"
    tc_line
    tc_prompt "Seleccione puerto a eliminar"
    read -r sel

    [[ "$sel" == "0" || -z "$sel" ]] && return

    if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#ports[@]} )); then
        tc_msg_err "Opción no válida."
        tc_pause
        return
    fi

    local target_port="${ports[$((sel - 1))]}"

    if ! tc_confirm "¿Está seguro de eliminar el puerto SSL $target_port?"; then
        return
    fi

    # Eliminar sección en stunnel.conf
    local tmp_conf="/tmp/stunnel_$$.conf"
    awk -v p="$target_port" '
        /^\[/ { in_sec=1; sec_lines=$0; has_p=0; next }
        in_sec {
            sec_lines = sec_lines "\n" $0
            if ($0 ~ "accept[ \t]*=[ \t]*" p "($|[ \t])") has_p=1
            next
        }
        { print }
        END {
            # flushes handled in block transitions
        }
    ' "$TC_STUNNEL_CONF" > "$tmp_conf" 2>/dev/null

    # Método seguro por secciones
    perl -0777 -pe 's/\[[^\]]+\]\s*accept\s*=\s*'"$target_port"'\s*connect\s*=\s*[^\n]+\n*//g' "$TC_STUNNEL_CONF" > "$tmp_conf" 2>/dev/null || \
    sed -i "/accept = ${target_port}/,+1d" "$TC_STUNNEL_CONF"

    if [[ -s "$tmp_conf" ]]; then
        mv "$tmp_conf" "$TC_STUNNEL_CONF"
    fi

    systemctl restart stunnel4 >/dev/null 2>&1 || service stunnel4 restart >/dev/null 2>&1 || true
    tc_msg_ok "Puerto SSL $target_port eliminado."
    tc_pause
}

# ── 3. DETENER / DESACTIVAR STUNNEL ───────────────────────────
tc_stunnel_stop() {
    systemctl stop stunnel4 >/dev/null 2>&1 || true
    systemctl disable stunnel4 >/dev/null 2>&1 || true
    tc_msg_ok "Servicio Stunnel4 detenido y desactivado."
    tc_pause
}

tc_stunnel_activate() {
    if tc_stunnel_has_ports; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl enable stunnel4 >/dev/null 2>&1 || true
        systemctl restart stunnel4 >/dev/null 2>&1 || service stunnel4 restart >/dev/null 2>&1

        if tc_stunnel_is_running; then
            tc_msg_ok "SSL Tunnel activado correctamente."
        else
            tc_msg_err "No se pudo activar SSL Tunnel. Revise que los puertos configurados no esten ocupados."
            tc_stunnel_diag
        fi
        tc_pause
    else
        tc_stunnel_add_port
    fi
}

# ── MENÚ PRINCIPAL STUNNEL ────────────────────────────────────
tc_stunnel_menu() {
    while true; do
        tc_clear
        tc_title "STUNNEL (SSL TUNNEL) $(tc_stunnel_status_mark)"

        if ! tc_stunnel_is_running; then
            tc_opt "1" "ACTIVAR STUNNEL (SSL TUNNEL)"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line

            tc_prompt
            read -r opt

            case "$opt" in
                1|01) tc_stunnel_activate ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        else
            printf '%bREDIRECCIONES SSL ACTIVAS:%b\n' "$TC_DARK_GREEN" "$TC_NC"
            tc_stunnel_list_active_ports
            tc_line

            tc_opt "1" "AGREGAR PUERTO SSL / REDIRECCIÓN LOCAL"
            tc_opt "2" "ELIMINAR PUERTO SSL"
            tc_opt "3" "REINICIAR SERVICIO STUNNEL"
            tc_opt "4" "DETENER / DESACTIVAR STUNNEL"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line

            tc_prompt
            read -r opt

            case "$opt" in
                1|01) tc_stunnel_add_port ;;
                2|02) tc_stunnel_del_port ;;
                3|03)
                    systemctl restart stunnel4 >/dev/null 2>&1 || service stunnel4 restart >/dev/null 2>&1 || true
                    tc_msg_ok "Servicio Stunnel4 reiniciado."
                    tc_pause
                    ;;
                4|04) tc_stunnel_stop ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        fi
    done
}
