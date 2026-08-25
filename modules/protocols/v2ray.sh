#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/v2ray.sh
#  Gestión completa de Xray-core / V2Ray (VMess + VLESS Unificados)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════

TC_XRAY_DIR="/etc/tunnelcore/v2ray"
TC_XRAY_CONF="${TC_XRAY_DIR}/config.json"
TC_XRAY_USERS="${TC_XRAY_DIR}/users.db"
TC_XRAY_DOMAIN_FILE="${TC_XRAY_DIR}/domain"
TC_XRAY_CERT="${TC_XRAY_DIR}/server.crt"
TC_XRAY_KEY="${TC_XRAY_DIR}/server.key"
TC_XRAY_SERVICE="/etc/systemd/system/xray.service"
TC_XRAY_BIN="/usr/local/bin/xray"

# ── Estado del servicio ───────────────────────────────────────
tc_xray_is_installed() {
    [[ -x "$TC_XRAY_BIN" && -f "$TC_XRAY_CONF" ]]
}

tc_xray_is_running() {
    systemctl is-active --quiet xray 2>/dev/null || pgrep -x xray >/dev/null 2>&1
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

tc_xray_ensure_certs() {
    mkdir -p "$TC_XRAY_DIR"
    if [[ ! -f "$TC_XRAY_CERT" || ! -f "$TC_XRAY_KEY" ]]; then
        openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
            -keyout "$TC_XRAY_KEY" -out "$TC_XRAY_CERT" -subj "/CN=tunnelcore-v2ray" >/dev/null 2>&1 || true
        chmod 600 "$TC_XRAY_KEY" "$TC_XRAY_CERT" 2>/dev/null || true
    fi
}

# ── Descargar e instalar binario oficial de Xray-core ──────────
tc_xray_install_binary() {
    tc_require_cmd "curl" "curl"
    tc_require_cmd "unzip" "unzip"
    tc_require_cmd "jq" "jq"

    local arch asset
    arch="$(tc_detect_arch)"
    case "$arch" in
        amd64) asset="Xray-linux-64.zip" ;;
        arm64) asset="Xray-linux-arm64-v8a.zip" ;;
        arm)   asset="Xray-linux-arm32-v7a.zip" ;;
        *)
            tc_msg_err "Arquitectura no soportada para Xray: $arch"
            return 1
            ;;
    esac

    local xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/${asset}"
    local tmp_dir="/tmp/xray-install-$$"
    mkdir -p "$tmp_dir"

    tc_msg_ok "Descargando Xray-core para $arch..."
    if ! curl -fsSL --connect-timeout 5 --max-time 60 -o "${tmp_dir}/xray.zip" "$xray_url"; then
        wget -q --timeout=30 -O "${tmp_dir}/xray.zip" "$xray_url" || {
            tc_msg_err "Error descargando Xray desde GitHub Releases."
            rm -rf "$tmp_dir"
            return 1
        }
    fi

    unzip -q -o "${tmp_dir}/xray.zip" -d "$tmp_dir" >/dev/null 2>&1 || {
        tc_msg_err "Error al descomprimir el archivo de Xray."
        rm -rf "$tmp_dir"
        return 1
    }

    install -m 755 "${tmp_dir}/xray" "$TC_XRAY_BIN"
    rm -rf "$tmp_dir"

    mkdir -p /usr/local/share/xray /var/log/xray
    mkdir -p "$TC_XRAY_DIR"
    tc_xray_ensure_certs

    # Servicio systemd
    cat > "$TC_XRAY_SERVICE" <<EOF
[Unit]
Description=TunnelCore Xray-Core Service
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

# ── Generar config base multi-protocolo (VMess + VLESS) ───────
tc_xray_write_base_config() {
    local port="${1:-80}" path="${2:-/tunnelcore}"
    local init_uuid
    init_uuid="$(tc_gen_uuid)"
    tc_xray_ensure_certs

    mkdir -p "$TC_XRAY_DIR" /var/log/xray
    cat > "$TC_XRAY_CONF" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "vmess-ws-in",
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${init_uuid}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "${path}"
        }
      }
    },
    {
      "tag": "vless-ws-in",
      "port": 8080,
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

    echo "admin | ${init_uuid} | $(date '+%Y-%m-%d' -d '+365 days' 2>/dev/null || echo '2030-01-01') | multi" > "$TC_XRAY_USERS"
    chmod 600 "$TC_XRAY_CONF" "$TC_XRAY_USERS"
}

# ── Instalar Xray desde cero ──────────────────────────────────
tc_xray_install() {
    tc_clear
    tc_title "INSTALAR XRAY (VMESS + VLESS)"

    local port path
    printf '%bPuerto VMess principal [Enter = 80]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r port
    [[ -z "$port" ]] && port="80"

    if ! tc_valid_port "$port"; then
        tc_msg_err "Puerto no válido."
        tc_pause
        return 1
    fi

    printf '%bPath WebSocket [Enter = /tunnelcore]:%b ' "$TC_DARK_GREEN" "$TC_NC"
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
        tc_msg_ok "Xray instalado y activo en puerto $port (VMess) y 8080 (VLESS) con path '$path'."
    else
        tc_msg_warn "Xray instalado. Verifique el estado con journalctl -u xray."
    fi
    tc_pause
}

# ── Añadir cuenta V2Ray (Universal: VMess + VLESS con el mismo UUID) ──
tc_xray_add_user() {
    if ! tc_xray_is_installed; then
        tc_msg_warn "Xray no está instalado. Instálelo primero."
        tc_pause
        return
    fi

    tc_clear
    tc_title "AÑADIR CUENTA V2RAY (UNIVERSAL)"

    local nick uuid days expiry_date

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

    # 2. UUID Único Universal
    uuid="$(tc_gen_uuid)"

    # 3. Modo de conexión (Directo IP vs Cloudflare CDN + SNI)
    local vps_ip cur_domain base_port ext_port tls_mode="none" add_host sni_host="" host_header=""
    vps_ip="$(tc_public_ip)"
    base_port="$(jq -r '.inbounds[0].port // 80' "$TC_XRAY_CONF" 2>/dev/null)"
    cur_domain="$(cat "$TC_XRAY_DOMAIN_FILE" 2>/dev/null || echo "")"

    printf '\n%bModo de Conexión / Seguridad:%b\n' "$TC_WHITE" "$TC_NC"
    tc_opt "1" "DIRECTO A IP (Sin TLS / HTTP WS - Puerto $base_port)"
    tc_opt "2" "CLOUDFLARE CDN / DOMINIO (Con TLS 443 + SNI Bug Host)"
    tc_prompt "Opción [1-2]"
    read -r conn_opt

    if [[ "$conn_opt" == "2" ]]; then
        tls_mode="tls"
        ext_port="443"
        if [[ -n "$cur_domain" ]]; then
            printf '\n%bDominio CDN (Enter para usar %s):%b ' "$TC_DARK_GREEN" "$cur_domain" "$TC_NC"
            read -r input_domain
            [[ -n "$input_domain" ]] && add_host="$input_domain" || add_host="$cur_domain"
        else
            while true; do
                printf '\n%bDominio CDN (ej: midominio.com):%b ' "$TC_DARK_GREEN" "$TC_NC"
                read -r add_host
                [[ -n "$add_host" ]] && break
                tc_msg_err "Debe ingresar un dominio."
            done
            echo "$add_host" > "$TC_XRAY_DOMAIN_FILE"
        fi

        printf '%bSNI / Bug Host (ej: bug.operadora.com) [Enter para usar %s]:%b ' "$TC_DARK_GREEN" "$add_host" "$TC_NC"
        read -r input_sni
        if [[ -n "$input_sni" ]]; then
            sni_host="$input_sni"
            host_header="$input_sni"
        else
            sni_host="$add_host"
            host_header="$add_host"
        fi
    else
        tls_mode="none"
        ext_port="$base_port"
        add_host="$vps_ip"
        sni_host=""
        host_header=""
    fi

    # 4. Días de validez
    printf '\n%bDuración en días [1-365] (Enter = 30):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r days
    [[ -z "$days" ]] && days="30"
    expiry_date="$(date '+%Y-%m-%d' -d "+${days} days" 2>/dev/null || echo "2030-01-01")"

    # 5. Insertar cliente en TODOS los inbounds (VMess + VLESS)
    local tmp_json="${TC_XRAY_CONF}.tmp"
    tc_backup_file "$TC_XRAY_CONF"

    jq --arg id "$uuid" '
      .inbounds |= map(
        if (.protocol == "vmess" and ((.settings.clients? | type) == "array")) then
          if (.settings.clients | any(.id == $id)) then . else .settings.clients += [{"id": $id, "alterId": 0}] end
        elif (.protocol == "vless" and ((.settings.clients? | type) == "array")) then
          if (.settings.clients | any(.id == $id)) then . else .settings.clients += [{"id": $id, "level": 0}] end
        else
          .
        end
      )
    ' "$TC_XRAY_CONF" > "$tmp_json" && mv "$tmp_json" "$TC_XRAY_CONF"

    echo "${nick} | ${uuid} | ${expiry_date} | universal" >> "$TC_XRAY_USERS"
    systemctl restart xray >/dev/null 2>&1

    # 6. Generar AMBOS enlaces (VMess y VLESS) con el mismo UUID y Path
    local path
    path="$(jq -r '.inbounds[0].streamSettings.wsSettings.path // "/tunnelcore"' "$TC_XRAY_CONF" 2>/dev/null)"
    [[ -z "$path" || "$path" == "null" ]] && path="/tunnelcore"

    # Enlace VMess
    local vmess_json b64 uri_vmess
    vmess_json=$(cat <<EOF
{
  "v": "2",
  "ps": "${nick}-VMess",
  "add": "${add_host}",
  "port": "${ext_port}",
  "id": "${uuid}",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "none",
  "host": "${host_header}",
  "path": "${path}",
  "tls": "${tls_mode}",
  "sni": "${sni_host}",
  "alpn": "",
  "fp": ""
}
EOF
)
    b64="$(printf '%s' "$vmess_json" | base64 | tr -d '\n\r ')"
    uri_vmess="vmess://${b64}"

    # Enlace VLESS
    local enc_path uri_vless
    enc_path="$(printf '%s' "$path" | sed 's/\//%2F/g')"
    if [[ "$tls_mode" == "tls" ]]; then
        uri_vless="vless://${uuid}@${add_host}:${ext_port}?type=ws&security=tls&sni=${sni_host}&host=${host_header}&path=${enc_path}#${nick}-VLESS"
    else
        uri_vless="vless://${uuid}@${add_host}:${ext_port}?type=ws&security=none&path=${enc_path}#${nick}-VLESS"
    fi

    # 7. Mostrar Ficha con ambos protocolos listos
    tc_clear
    tc_title "CUENTA V2RAY CREADA CON ÉXITO"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "USUARIO:" "$TC_NC" "$TC_WHITE" "$nick" "$TC_NC"
    printf '%b%-20s%b %bUNIVERSAL (VMess + VLESS)%b\n' "$TC_DARK_GREEN" "PROTOCOLO:" "$TC_NC" "$TC_GREEN" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "SERVIDOR / HOST:" "$TC_NC" "$TC_WHITE" "$add_host" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "PUERTO CONEXIÓN:" "$TC_NC" "$TC_WHITE" "$ext_port" "$TC_NC"
    [[ "$tls_mode" == "tls" ]] && printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "SNI / BUG HOST:" "$TC_NC" "$TC_WHITE" "$sni_host" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "UUID / ID:" "$TC_NC" "$TC_WHITE" "$uuid" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "PATH WS:" "$TC_NC" "$TC_WHITE" "$path" "$TC_NC"
    printf '%b%-20s%b %b%s (%s días)%b\n' "$TC_DARK_GREEN" "EXPIRA:" "$TC_NC" "$TC_WHITE" "$expiry_date" "$days" "$TC_NC"
    tc_line
    printf '%bENLACE VMESS (Para v2rayNG, HTTP Custom, Napsternet):%b\n' "$TC_YELLOW" "$TC_NC"
    printf '%b%s%b\n\n' "$TC_CYAN" "$uri_vmess" "$TC_NC"
    printf '%bENLACE VLESS (Para v2rayNG, Napsternet, Shadowrocket):%b\n' "$TC_YELLOW" "$TC_NC"
    printf '%b%s%b\n' "$TC_CYAN" "$uri_vless" "$TC_NC"
    tc_line
    tc_pause
}

# ── Listar cuentas Xray ───────────────────────────────────────
tc_xray_list_users() {
    tc_clear
    tc_title "CUENTAS V2RAY / XRAY REGISTRADAS"

    if [[ ! -f "$TC_XRAY_USERS" || ! -s "$TC_XRAY_USERS" ]]; then
        tc_msg_warn "No hay cuentas de Xray registradas."
        tc_pause
        return
    fi

    printf '%b%-16s %-38s %-12s %-10s%b\n' "$TC_YELLOW" "USUARIO" "UUID" "EXPIRA" "TIPO" "$TC_NC"
    tc_line

    local nick uuid exp proto
    while IFS='|' read -r nick uuid exp proto || [[ -n "$nick" ]]; do
        nick="$(echo "$nick" | tr -d ' ')"
        uuid="$(echo "$uuid" | tr -d ' ')"
        exp="$(echo "$exp" | tr -d ' ')"
        proto="$(echo "$proto" | tr -d ' ')"
        [[ -z "$nick" ]] && continue
        printf '%b%-16s%b %b%-38s%b %b%-12s%b %b%-10s%b\n' \
            "$TC_WHITE" "$nick" "$TC_NC" \
            "$TC_DARK_GREEN" "$uuid" "$TC_NC" \
            "$TC_PALE_GOLD" "$exp" "$TC_NC" \
            "$TC_CYAN" "$proto" "$TC_NC"
    done < "$TC_XRAY_USERS"

    tc_line
    tc_pause
}

# ── Eliminar cuenta Xray ──────────────────────────────────────
tc_xray_del_user() {
    tc_clear
    tc_title "ELIMINAR CUENTA V2RAY"

    if [[ ! -f "$TC_XRAY_USERS" || ! -s "$TC_XRAY_USERS" ]]; then
        tc_msg_warn "No hay cuentas de Xray para eliminar."
        tc_pause
        return
    fi

    printf '%bIngrese el nombre del usuario a eliminar:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r target_nick
    target_nick="$(echo "$target_nick" | tr -d ' ')"

    local target_uuid
    target_uuid="$(grep -E "^[[:space:]]*${target_nick}[[:space:]]*\|" "$TC_XRAY_USERS" | cut -d'|' -f2 | tr -d ' ' || true)"

    if [[ -z "$target_uuid" ]]; then
        tc_msg_err "Usuario '$target_nick' no encontrado."
        tc_pause
        return
    fi

    if ! tc_confirm "¿Eliminar la cuenta '$target_nick' ($target_uuid)?"; then
        return
    fi

    local tmp_json="${TC_XRAY_CONF}.tmp"
    jq --arg id "$target_uuid" '
      .inbounds |= map(
        if ((.settings.clients? | type) == "array") then
          .settings.clients |= map(select(.id != $id))
        else
          .
        end
      )
    ' "$TC_XRAY_CONF" > "$tmp_json" && mv "$tmp_json" "$TC_XRAY_CONF"

    sed -i "/^[[:space:]]*${target_nick}[[:space:]]*|/d" "$TC_XRAY_USERS"
    systemctl restart xray >/dev/null 2>&1

    tc_msg_ok "Cuenta '$target_nick' eliminada de Xray."
    tc_pause
}

# ── Menú Principal V2Ray / Xray ───────────────────────────────
tc_xray_menu() {
    while true; do
        tc_clear
        tc_title "GESTIÓN DE V2RAY / XRAY $(tc_xray_status_mark)"

        if ! tc_xray_is_installed; then
            tc_opt "1" "INSTALAR XRAY (VMESS + VLESS)"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_xray_install ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        else
            local cur_dom
            cur_dom="$(cat "$TC_XRAY_DOMAIN_FILE" 2>/dev/null || echo "No configurado")"

            printf '%bDOMINIO CDN:%b %b%s%b  %bESTADO:%b %b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$cur_dom" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$(tc_xray_status_mark)"
            tc_line
            tc_opt "1" "AÑADIR CUENTA (UNIVERSAL: VMESS + VLESS)"
            tc_opt "2" "LISTAR CUENTAS"
            tc_opt "3" "ELIMINAR CUENTA"
            tc_line
            tc_opt "4" "CAMBIAR DOMINIO CDN / HOST"
            tc_opt "5" "REINICIAR SERVICIO XRAY"
            tc_opt "6" "VER LOGS EN TIEMPO REAL"
            tc_opt "7" "REINSTALAR XRAY"
            tc_opt "8" "DESINSTALAR XRAY"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt

            case "$opt" in
                1|01) tc_xray_add_user ;;
                2|02) tc_xray_list_users ;;
                3|03) tc_xray_del_user ;;
                4|04)
                    printf '%bNuevo Dominio CDN:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r nd
                    if [[ -n "$nd" ]]; then
                        echo "$nd" > "$TC_XRAY_DOMAIN_FILE"
                        tc_msg_ok "Dominio actualizado a $nd."
                    fi
                    tc_pause
                    ;;
                5|05)
                    systemctl restart xray >/dev/null 2>&1
                    tc_msg_ok "Servicio Xray reiniciado."
                    tc_pause
                    ;;
                6|06)
                    tc_clear
                    tc_title "LOGS XRAY EN VIVO (Ctrl+C para salir)"
                    journalctl -u xray -f --no-pager
                    ;;
                7|07)
                    tc_xray_install
                    ;;
                8|08)
                    if tc_confirm "¿Está seguro de desinstalar Xray por completo?"; then
                        systemctl stop xray >/dev/null 2>&1 || true
                        systemctl disable xray >/dev/null 2>&1 || true
                        rm -f "$TC_XRAY_SERVICE" "$TC_XRAY_BIN"
                        rm -rf "$TC_XRAY_DIR"
                        systemctl daemon-reload >/dev/null 2>&1 || true
                        tc_msg_ok "Xray desinstalado."
                        tc_pause
                    fi
                    ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        fi
    done
}
