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
        break
    done

    printf '%bPuerto destino local a redirigir (SSH=22, Dropbear=110/443, WS=80) [Enter = 22]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r target
    [[ -z "$target" ]] && target="22"
    [[ "$target" =~ ^[0-9]+$ ]] || target="22"

    local tag="ssl-${port}"
    cat >> "$TC_STUNNEL_CONF" <<EOF

[${tag}]
accept = ${port}
connect = 127.0.0.1:${target}
EOF

    # Habilitar en /etc/default/stunnel4
    if [[ -f /etc/default/stunnel4 ]]; then
        sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || true
    fi

    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable stunnel4 >/dev/null 2>&1 || true
    systemctl restart stunnel4 >/dev/null 2>&1 || service stunnel4 restart >/dev/null 2>&1 || true

    if tc_stunnel_is_running; then
        tc_msg_ok "Puerto SSL $port configurado y activo redirigiendo a 127.0.0.1:$target."
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

# ── MENÚ PRINCIPAL STUNNEL ────────────────────────────────────
tc_stunnel_menu() {
    while true; do
        tc_clear
        tc_title "GESTIÓN DE STUNNEL (SSL TUNNEL) $(tc_stunnel_status_mark)"

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
    done
}
