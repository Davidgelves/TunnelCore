#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/v2ray.sh
#  Gestión de Xray / V2Ray (VLESS, VMess, WebSocket, XHTTP)
#  Usa el binario oficial de XTLS/Xray-core
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_XRAY_BIN="/usr/local/bin/xray"
TC_XRAY_DIR="/etc/xray"
TC_XRAY_CONF="${TC_XRAY_DIR}/config.json"
TC_XRAY_SERVICE="/etc/systemd/system/xray.service"
TC_XRAY_USERS="${TC_XRAY_DIR}/users.db"

tc_xray_is_installed() {
    [[ -x "$TC_XRAY_BIN" && -f "$TC_XRAY_CONF" ]]
}

tc_xray_is_running() {
    systemctl is-active --quiet xray 2>/dev/null
}

tc_xray_status_mark() {
    if tc_xray_is_running; then
        printf '%b[ON]%b' "$TC_GREEN" "$TC_NC"
    elif tc_xray_is_installed; then
        printf '%b[OFF]%b' "$TC_RED" "$TC_NC"
    else
        printf '%b[NO INSTALADO]%b' "$TC_YELLOW" "$TC_NC"
    fi
}

# ── Descargar e instalar Xray-core oficial ─────────────────────
tc_xray_install_binary() {
    tc_require_cmd "curl" "curl"
    tc_require_cmd "unzip" "unzip"
    tc_require_cmd "jq" "jq"

    local arch
    arch="$(tc_detect_arch)"
    local asset=""

    case "$arch" in
        amd64) asset="Xray-linux-64.zip" ;;
        arm64) asset="Xray-linux-arm64-v8a.zip" ;;
        arm)   asset="Xray-linux-arm32-v7a.zip" ;;
        386)   asset="Xray-linux-32.zip" ;;
        *)
            tc_msg_err "Arquitectura '$arch' no soportada por Xray."
            return 1
            ;;
    esac

    local url="https://github.com/XTLS/Xray-core/releases/latest/download/${asset}"
    local tmp_dir="/tmp/xray-install-$$"
    mkdir -p "$tmp_dir"

    tc_msg_ok "Descargando Xray-core oficial (${asset})..."
    if ! tc_download "$url" "${tmp_dir}/xray.zip" 3; then
        tc_msg_err "No se pudo descargar Xray-core desde GitHub."
        rm -rf "$tmp_dir"
        return 1
    fi

    unzip -qo "${tmp_dir}/xray.zip" -d "$tmp_dir" || {
        tc_msg_err "Error al descomprimir Xray."
        rm -rf "$tmp_dir"
        return 1
    }

    install -m 755 "${tmp_dir}/xray" "$TC_XRAY_BIN"
    mkdir -p "$TC_XRAY_DIR" "/var/log/xray"
    rm -rf "$tmp_dir"

    # Crear systemd service
    cat > "$TC_XRAY_SERVICE" <<EOF
[Unit]
Description=TunnelCore Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${TC_XRAY_BIN} run -config ${TC_XRAY_CONF}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable xray >/dev/null 2>&1
    return 0
}

# ── Generar config base ───────────────────────────────────────
tc_xray_write_base_config() {
    local port="${1:-8443}" path="${2:-/tunnelcore}"
    local init_uuid
    init_uuid="$(tc_gen_uuid)"

    mkdir -p "$TC_XRAY_DIR"
    cat > "$TC_XRAY_CONF" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "vless-ws-in",
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${init_uuid}",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "${path}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}
EOF

    # Registrar usuario inicial
    echo "admin | ${init_uuid} | $(date '+%Y-%m-%d' -d '+365 days' 2>/dev/null || echo '2030-01-01') | vless" > "$TC_XRAY_USERS"
    chmod 600 "$TC_XRAY_CONF" "$TC_XRAY_USERS"
}

# ── Instalar Xray desde cero ──────────────────────────────────
tc_xray_install() {
    tc_clear
    tc_title "INSTALAR XRAY (V2RAY)"

    local port path
    printf '%bPuerto de escucha [Enter = 8443]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r port
    [[ -z "$port" ]] && port="8443"

    if ! tc_valid_port "$port"; then
        tc_msg_err "Puerto no válido."
        tc_pause
        return 1
    fi

    if tc_port_in_use "$port"; then
        tc_msg_warn "El puerto $port ya está en uso por otro proceso."
        if ! tc_confirm "¿Desea continuar de todos modos?"; then
            return 1
        fi
    fi

    printf '%bPath WebSocket / XHTTP [Enter = /tunnelcore]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r path
    [[ -z "$path" ]] && path="/tunnelcore"
    [[ "$path" != /* ]] && path="/$path"

    tc_xray_install_binary || {
        tc_msg_err "Falló la instalación de Xray."
        tc_pause
        return 1
    }

    tc_xray_write_base_config "$port" "$path"
    systemctl restart xray >/dev/null 2>&1

    if tc_xray_is_running; then
        tc_msg_ok "Xray instalado y activo en el puerto $port con path '$path'."
    else
        tc_msg_err "Xray se instaló pero no pudo iniciar. Revise 'journalctl -u xray -n 20'."
    fi
    tc_pause
}

# ── Añadir cuenta V2Ray / Xray ────────────────────────────────
tc_xray_add_user() {
    if ! tc_xray_is_installed; then
        tc_msg_warn "Xray no está instalado. Instálelo primero."
        tc_pause
        return
    fi

    tc_clear
    tc_title "AÑADIR CUENTA XRAY (VLESS / VMESS)"

    local nick proto_choice proto_tag proto_name uuid days expiry_date

    # 1. Nickname
    while true; do
        printf '%bNombre / Alias para la cuenta:%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r nick
        nick="$(echo "$nick" | tr -d ' ')"
        [[ -z "$nick" ]] && { tc_msg_err "El nombre no puede estar vacío."; continue; }
        if grep -qE "^[[:space:]]*${nick}[[:space:]]*\|" "$TC_XRAY_USERS" 2>/dev/null; then
            tc_msg_err "Ya existe una cuenta con ese nombre."
            continue
        fi
        break
    done

    # 2. Protocolo
    printf '\n%bSeleccionar Protocolo:%b\n' "$TC_WHITE" "$TC_NC"
    tc_opt "1" "VLESS (Recomendado - Ligero y rápido)"
    tc_opt "2" "VMess"
    tc_prompt "Opción [1-2]"
    read -r proto_choice
    case "$proto_choice" in
        2) proto_tag="vmess"; proto_name="VMess" ;;
        *) proto_tag="vless"; proto_name="VLESS" ;;
    esac

    # 3. UUID
    uuid="$(tc_gen_uuid)"

    # 4. Días de validez
    printf '%bDuración en días [1-365] (Enter = 30):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r days
    [[ -z "$days" ]] && days="30"
    expiry_date="$(date '+%Y-%m-%d' -d "+${days} days" 2>/dev/null || echo "2030-01-01")"

    # 5. Insertar en config.json usando jq
    local tmp_json="${TC_XRAY_CONF}.tmp"
    tc_backup_file "$TC_XRAY_CONF"

    if [[ "$proto_tag" == "vless" ]]; then
        jq --arg id "$uuid" '
          .inbounds[0].settings.clients += [{"id": $id, "level": 0}]
        ' "$TC_XRAY_CONF" > "$tmp_json" && mv "$tmp_json" "$TC_XRAY_CONF"
    else
        jq --arg id "$uuid" '
          .inbounds[0].settings.clients += [{"id": $id, "alterId": 0}]
        ' "$TC_XRAY_CONF" > "$tmp_json" && mv "$tmp_json" "$TC_XRAY_CONF"
    fi

    echo "${nick} | ${uuid} | ${expiry_date} | ${proto_tag}" >> "$TC_XRAY_USERS"
    systemctl restart xray >/dev/null 2>&1

    # 6. Generar URI de conexión
    local port path vps_ip uri
    port="$(jq -r '.inbounds[0].port // 8443' "$TC_XRAY_CONF" 2>/dev/null)"
    path="$(jq -r '.inbounds[0].streamSettings.wsSettings.path // "/tunnelcore"' "$TC_XRAY_CONF" 2>/dev/null)"
    vps_ip="$(tc_public_ip)"

    if [[ "$proto_tag" == "vless" ]]; then
        local enc_path
        enc_path="$(printf '%s' "$path" | sed 's/\//%2F/g')"
        uri="vless://${uuid}@${vps_ip}:${port}?type=ws&security=none&path=${enc_path}#${nick}-TunnelCore"
    else
        local vmess_raw
        vmess_raw=$(cat <<EOF
{"v":"2","ps":"${nick}-TunnelCore","add":"${vps_ip}","port":"${port}","id":"${uuid}","aid":"0","scy":"auto","net":"ws","type":"none","host":"","path":"${path}","tls":""}
EOF
)
        local b64
        b64="$(printf '%s' "$vmess_raw" | base64 | tr -d '\n\r')"
        uri="vmess://${b64}"
    fi

    # 7. Mostrar Ficha
    tc_clear
    tc_title "CUENTA XRAY CREADA CON ÉXITO"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "USUARIO:" "$TC_NC" "$TC_WHITE" "$nick" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "PROTOCOLO:" "$TC_NC" "$TC_WHITE" "$proto_name" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "PUERTO:" "$TC_NC" "$TC_WHITE" "$port" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "UUID:" "$TC_NC" "$TC_WHITE" "$uuid" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "PATH WS:" "$TC_NC" "$TC_WHITE" "$path" "$TC_NC"
    printf '%b%-20s%b %b%s (%s días)%b\n' "$TC_DARK_GREEN" "EXPIRA:" "$TC_NC" "$TC_WHITE" "$expiry_date" "$days" "$TC_NC"
    tc_line
    printf '%bENLACE URI PARA IMPORTAR (v2rayNG / NapsternetV / etc.):%b\n\n' "$TC_YELLOW" "$TC_NC"
    printf '%b%s%b\n\n' "$TC_CYAN" "$uri" "$TC_NC"
    tc_line
    tc_pause
}

# ── Listar cuentas Xray ───────────────────────────────────────
tc_xray_list_users() {
    tc_clear
    tc_title "CUENTAS XRAY REGISTRADAS"

    if [[ ! -s "$TC_XRAY_USERS" ]]; then
        tc_msg_warn "No hay cuentas Xray registradas."
        tc_pause
        return
    fi

    printf '%b%-16s %-38s %-12s %s%b\n' "$TC_WHITE" "ALIAS" "UUID" "EXPIRA" "PROTO" "$TC_NC"
    tc_line

    while IFS='|' read -r nick uuid exp proto; do
        nick="$(echo "$nick" | xargs)"
        uuid="$(echo "$uuid" | xargs)"
        exp="$(echo "$exp" | xargs)"
        proto="$(echo "$proto" | xargs)"
        [[ -z "$nick" ]] && continue
        printf '%b%-16s%b %b%-38s%b %b%-12s%b %b%s%b\n' \
            "$TC_CYAN" "$nick" "$TC_NC" \
            "$TC_WHITE" "$uuid" "$TC_NC" \
            "$TC_PALE_GOLD" "$exp" "$TC_NC" \
            "$TC_GREEN" "$proto" "$TC_NC"
    done < "$TC_XRAY_USERS"

    tc_line
    tc_pause
}

# ── Eliminar cuenta Xray ──────────────────────────────────────
tc_xray_del_user() {
    tc_clear
    tc_title "ELIMINAR CUENTA XRAY"

    if [[ ! -s "$TC_XRAY_USERS" ]]; then
        tc_msg_warn "No hay cuentas registradas."
        tc_pause
        return
    fi

    local -a n_list=() u_list=()
    while IFS='|' read -r nick uuid _exp _proto; do
        nick="$(echo "$nick" | xargs)"
        uuid="$(echo "$uuid" | xargs)"
        [[ -n "$nick" ]] && { n_list+=("$nick"); u_list+=("$uuid"); }
    done < "$TC_XRAY_USERS"

    for i in "${!n_list[@]}"; do
        tc_opt "$((i + 1))" "${n_list[$i]} (${u_list[$i]})"
    done
    tc_line
    tc_opt "0" "CANCELAR"
    tc_line

    local sel
    tc_prompt "Seleccione cuenta a eliminar"
    read -r sel
    [[ "$sel" == "0" ]] && return
    if [[ ! "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#n_list[@]} )); then
        tc_msg_err "Opción no válida."
        tc_pause
        return
    fi

    local del_nick="${n_list[$((sel - 1))]}"
    local del_uuid="${u_list[$((sel - 1))]}"

    if tc_confirm "¿Eliminar cuenta '$del_nick'?"; then
        local tmp_json="${TC_XRAY_CONF}.tmp"
        jq --arg id "$del_uuid" '
          .inbounds[0].settings.clients |= map(select(.id != $id))
        ' "$TC_XRAY_CONF" > "$tmp_json" && mv "$tmp_json" "$TC_XRAY_CONF"

        sed -i "/^[[:space:]]*${del_nick}[[:space:]]*|/d" "$TC_XRAY_USERS" 2>/dev/null || true
        systemctl restart xray >/dev/null 2>&1
        tc_msg_ok "Cuenta '$del_nick' eliminada."
    fi
    tc_pause
}

# ── Desinstalar Xray ──────────────────────────────────────────
tc_xray_uninstall() {
    tc_clear
    tc_title "DESINSTALAR XRAY"

    if ! tc_xray_is_installed; then
        tc_msg_warn "Xray no está instalado."
        tc_pause
        return
    fi

    if tc_confirm "¿Está seguro de desinstalar Xray por completo?"; then
        systemctl stop xray >/dev/null 2>&1 || true
        systemctl disable xray >/dev/null 2>&1 || true
        rm -f "$TC_XRAY_SERVICE" "$TC_XRAY_BIN"
        rm -rf "$TC_XRAY_DIR" "/var/log/xray"
        systemctl daemon-reload >/dev/null 2>&1
        tc_msg_ok "Xray desinstalado correctamente."
    fi
    tc_pause
}

# ── Menú Xray ─────────────────────────────────────────────────
tc_xray_menu() {
    while true; do
        tc_clear
        tc_title "GESTIÓN XRAY / V2RAY $(tc_xray_status_mark)"

        if ! tc_xray_is_installed; then
            tc_opt "1" "INSTALAR XRAY (VLESS / VMESS)"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_xray_install ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        else
            tc_opt "1" "AÑADIR CUENTA (VLESS / VMESS)"
            tc_opt "2" "LISTAR CUENTAS"
            tc_opt "3" "ELIMINAR CUENTA"
            tc_opt "4" "REINICIAR SERVICIO XRAY"
            tc_opt "5" "VER LOGS DE XRAY"
            tc_opt "6" "DESINSTALAR XRAY"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_xray_add_user ;;
                2|02) tc_xray_list_users ;;
                3|03) tc_xray_del_user ;;
                4|04) systemctl restart xray >/dev/null 2>&1 && tc_msg_ok "Xray reiniciado." && tc_pause ;;
                5|05) journalctl -u xray -n 30 --no-pager && tc_pause ;;
                6|06) tc_xray_uninstall ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        fi
    done
}

