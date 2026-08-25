#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/limiter.sh
#  Limitador automático de conexiones SSH por usuario
#  Ejecutado de forma limpia mediante systemd (sin screens huérfanos)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════

TC_LIMITER_SCRIPT="/usr/local/bin/tunnelcore-limiter"
TC_LIMITER_SERVICE="/etc/systemd/system/tunnelcore-limiter.service"

tc_limiter_is_running() {
    systemctl is-active --quiet tunnelcore-limiter 2>/dev/null
}

tc_limiter_install_daemon() {
    # Generar script ejecutable del limitador
    cat > "$TC_LIMITER_SCRIPT" <<'EOF'
#!/bin/bash
# TunnelCore — Daemon Limitador de Conexiones
DB="/etc/tunnelcore/users.db"
INTERVAL=10

while true; do
    [[ -f "$DB" ]] || { sleep "$INTERVAL"; continue; }

    while IFS='|' read -r user _pass _exp limit; do
        user="$(echo "$user" | xargs)"
        limit="$(echo "$limit" | xargs)"
        [[ -z "$user" || -z "$limit" ]] && continue
        [[ ! "$limit" =~ ^[0-9]+$ ]] && continue
        (( limit < 1 )) && continue

        # Obtener PIDs de sesiones SSH activas del usuario (ordenadas cronológicamente)
        pids=($(pgrep -u "$user" -f 'sshd:.*@' 2>/dev/null || true))
        count="${#pids[@]}"

        if (( count > limit )); then
            excess=$(( count - limit ))
            # Matar los PIDs más antiguos o más nuevos excedentes
            for (( i=0; i < excess; i++ )); do
                kill -9 "${pids[$i]}" 2>/dev/null || true
            done
        fi
    done < "$DB"

    sleep "$INTERVAL"
done
EOF
    chmod +x "$TC_LIMITER_SCRIPT"

    # Generar systemd service
    cat > "$TC_LIMITER_SERVICE" <<EOF
[Unit]
Description=TunnelCore Connection Limiter Daemon
After=network.target

[Service]
Type=simple
ExecStart=${TC_LIMITER_SCRIPT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
}

tc_limiter_start() {
    tc_limiter_install_daemon
    systemctl enable tunnelcore-limiter >/dev/null 2>&1
    systemctl restart tunnelcore-limiter >/dev/null 2>&1
}

tc_limiter_stop() {
    systemctl stop tunnelcore-limiter >/dev/null 2>&1 || true
    systemctl disable tunnelcore-limiter >/dev/null 2>&1 || true
}

tc_limiter_toggle() {
    if tc_limiter_is_running; then
        tc_limiter_stop
        tc_msg_ok "Limitador desactivado."
    else
        tc_limiter_start
        tc_msg_ok "Limitador activado y en ejecución."
    fi
    tc_pause
}

tc_limiter_menu() {
    while true; do
        tc_clear
        tc_title "LIMITADOR DE CONEXIONES"

        local st
        if tc_limiter_is_running; then
            st="${TC_GREEN}[ACTIVADO]${TC_NC}"
        else
            st="${TC_RED}[DESACTIVADO]${TC_NC}"
        fi

        printf '%bESTADO:%b %b\n' "$TC_DARK_GREEN" "$TC_NC" "$st"
        tc_line
        tc_opt "1" "ACTIVAR / DESACTIVAR LIMITADOR"
        tc_opt "2" "REINICIAR SERVICIO LIMITADOR"
        tc_opt "3" "VER LOGS / ESTADO SYSTEMD"
        tc_line
        tc_opt "0" "VOLVER"
        tc_line
        tc_prompt
        read -r opt

        case "$opt" in
            1|01) tc_limiter_toggle ;;
            2|02)
                systemctl restart tunnelcore-limiter >/dev/null 2>&1
                tc_msg_ok "Limitador reiniciado."
                tc_pause
                ;;
            3|03)
                tc_clear
                tc_title "ESTADO SYSTEMD LIMITADOR"
                systemctl status tunnelcore-limiter --no-pager
                tc_pause
                ;;
            0|00) break ;;
            *) tc_msg_err "Opción no válida."; sleep 1 ;;
        esac
    done
}

