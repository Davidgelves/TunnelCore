#!/bin/bash
# ─────────────────────────────────────────────────────────────────
#  TunnelCore — modules/protocols/v2ray.sh
#  Gestor Universal de V2Ray / Xray (VMess TLS 443 + HTTP 80 + VLESS)
#  Autor: J DAVID AG
# ─────────────────────────────────────────────────────────────────

TC_XRAY_DIR="/etc/tunnelcore/v2ray"
TC_XRAY_CONF="${TC_XRAY_DIR}/config.json"
TC_XRAY_USERS="${TC_XRAY_DIR}/users.db"
TC_XRAY_DOMAIN_FILE="${TC_XRAY_DIR}/domain"
TC_XRAY_PATH_FILE="${TC_XRAY_DIR}/path"
TC_XRAY_CERT="${TC_XRAY_DIR}/server.crt"
TC_XRAY_KEY="${TC_XRAY_DIR}/server.key"
TC_XRAY_SERVICE="/etc/systemd/system/xray.service"
TC_XRAY_BIN="/usr/local/bin/xray"

# ── Estado del servicio ───────────────────────────────────────
tc_xray_is_installed() {
    [[ -x "$TC_XRAY_BIN" && -f "$TC_XRAY_CONF" ]]
}

tc_xray_is_running() {
    systemctl is-active --quiet xray 2>/dev/null || pgrep -x xray >/dev/null 2>&1 || (command -v ss >/dev/null 2>&1 && ss -tunlp 2>/dev/null | grep -qE 'xray|/xray')
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

tc_xray_restart_service() {
    mkdir -p "$TC_XRAY_DIR" /var/log/xray
    chmod 755 /var/log/xray 2>/dev/null || true
    tc_xray_ensure_certs
    systemctl stop apache2 >/dev/null 2>&1 || true
    systemctl disable apache2 >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable xray >/dev/null 2>&1
    tc_xray_restart_service >/dev/null 2>&1
}

# ── Generar Certificados SSL Permisivos (Acepta cualquier SNI) ──
tc_xray_ensure_certs() {
    mkdir -p "$TC_XRAY_DIR"
    if [[ ! -f "$TC_XRAY_CERT" || ! -f "$TC_XRAY_KEY" ]]; then
        openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
            -keyout "$TC_XRAY_KEY" -out "$TC_XRAY_CERT" \
            -subj "/C=US/ST=State/L=City/O=TunnelCore/OU=VPN/CN=*" >/dev/null 2>&1 || true
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

    tc_msg_ok "Descargando Xray-core oficial para $arch..."
    if ! curl -fsSL --connect-timeout 8 --max-time 90 -o "${tmp_dir}/xray.zip" "$xray_url"; then
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

    # Crear servicio systemd
    cat > "$TC_XRAY_SERVICE" <<EOF
[Unit]
Description=TunnelCore Xray-Core Multi-Protocol Service
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

# ── Generar config base (Multi-Inbound Permisivo: 443 TLS + 80 HTTP + 8443 VLESS) ──
tc_xray_write_base_config() {
    local path="${1:-/tunnelcore}"
    local init_uuid
    init_uuid="$(tc_gen_uuid)"
    tc_xray_ensure_certs

    mkdir -p "$TC_XRAY_DIR" /var/log/xray
    echo "$path" > "$TC_XRAY_PATH_FILE"

    cat > "$TC_XRAY_CONF" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "vmess-tls-443",
      "port": 443,
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
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${TC_XRAY_CERT}",
              "keyFile": "${TC_XRAY_KEY}"
            }
          ]
        },
        "wsSettings": {
          "path": "${path}"
        }
      }
    },
    {
      "tag": "vmess-http-80",
      "port": 80,
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
      "tag": "vless-tls-8443",
      "port": 8443,
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
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${TC_XRAY_CERT}",
              "keyFile": "${TC_XRAY_KEY}"
            }
          ]
        },
        "wsSettings": {
          "path": "${path}"
        }
      }
    },
    {
      "tag": "vless-http-8080",
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
}

# ── Generador de Enlaces URI ──────────────────────────────────
tc_xray_show_user_links() {
    local nick="$1" uuid="$2"
    local vps_ip cur_domain cur_path
    vps_ip="$(tc_public_ip)"
    cur_domain="$(cat "$TC_XRAY_DOMAIN_FILE" 2>/dev/null || echo "$vps_ip")"
    [[ -z "$cur_domain" ]] && cur_domain="$vps_ip"
    cur_path="$(cat "$TC_XRAY_PATH_FILE" 2>/dev/null || echo "/tunnelcore")"
    [[ -z "$cur_path" ]] && cur_path="/tunnelcore"

    # 1. VMess 443 TLS (SNI Permisivo para Apps)
    local json_443 raw_443 b64_443 vmess_443_uri
    json_443="{\"v\":\"2\",\"ps\":\"${nick} [TLS 443]\",\"add\":\"${cur_domain}\",\"port\":\"443\",\"id\":\"${uuid}\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${cur_domain}\",\"path\":\"${cur_path}\",\"tls\":\"tls\",\"sni\":\"${cur_domain}\",\"alpn\":\"\"}"
    b64_443="$(printf '%s' "$json_443" | base64 | tr -d '\n\r')"
    vmess_443_uri="vmess://${b64_443}"

    # 2. VMess 80 HTTP (Sin TLS / Cloudflare CDN)
    local json_80 b64_80 vmess_80_uri
    json_80="{\"v\":\"2\",\"ps\":\"${nick} [HTTP 80]\",\"add\":\"${cur_domain}\",\"port\":\"80\",\"id\":\"${uuid}\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${cur_domain}\",\"path\":\"${cur_path}\",\"tls\":\"none\",\"sni\":\"\",\"alpn\":\"\"}"
    b64_80="$(printf '%s' "$json_80" | base64 | tr -d '\n\r')"
    vmess_80_uri="vmess://${b64_80}"

    # 3. VLESS 8443 TLS
    local vless_uri="vless://${uuid}@${cur_domain}:8443?encryption=none&security=tls&type=ws&path=${cur_path}&sni=${cur_domain}#${nick}%20[VLESS]"

    tc_line
    printf '%bDATOS DE CUENTA:%b %b%s%b\n' "$TC_YELLOW" "$TC_NC" "$TC_WHITE" "$nick" "$TC_NC"
    printf '%bUUID / ID      :%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$uuid" "$TC_NC"
    printf '%bIP SERVIDOR    :%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$vps_ip" "$TC_NC"
    printf '%bDOMINIO / HOST :%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "$cur_domain" "$TC_NC"
    printf '%bPATH WEBSOCKET :%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_CYAN" "$cur_path" "$TC_NC"
    tc_line

    printf '%b[OPCIÓN 1] VMess TLS (Puerto 443 + SNI Bug)%b\n' "$TC_GREEN" "$TC_NC"
    printf '%b%s%b\n\n' "$TC_CYAN" "$vmess_443_uri" "$TC_NC"

    printf '%b[OPCIÓN 2] VMess HTTP (Puerto 80 / Cloudflare CDN / Sin TLS)%b\n' "$TC_GREEN" "$TC_NC"
    printf '%b%s%b\n\n' "$TC_CYAN" "$vmess_80_uri" "$TC_NC"

    printf '%b[OPCIÓN 3] VLESS TLS (Puerto 8443)%b\n' "$TC_GREEN" "$TC_NC"
    printf '%b%s%b\n' "$TC_CYAN" "$vless_uri" "$TC_NC"
    tc_line
}

# ── Instalador Interactivo ────────────────────────────────────
tc_xray_install() {
    tc_clear
    tc_title "INSTALACIÓN MAESTRA DE V2RAY / XRAY"

    local path
    printf '%bPath WebSocket [Enter = /tunnelcore]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r path
    [[ -z "$path" ]] && path="/tunnelcore"
    [[ "$path" != /* ]] && path="/$path"

    local dom
    local def_ip="$(tc_public_ip)"
    printf '%bDominio o Subdominio [Enter = %s]:%b ' "$TC_DARK_GREEN" "$def_ip" "$TC_NC"
    read -r dom
    [[ -z "$dom" ]] && dom="$def_ip"
    mkdir -p "$TC_XRAY_DIR"
    echo "$dom" > "$TC_XRAY_DOMAIN_FILE"

    tc_xray_install_binary || {
        tc_msg_err "Falló la descarga del binario de Xray."
        tc_pause
        return 1
    }

    tc_xray_write_base_config "$path"
    tc_xray_restart_service >/dev/null 2>&1

    if tc_xray_is_running; then
        tc_msg_ok "Xray instalado y activo con puertos 443 (TLS), 80 (HTTP) y 8443 (VLESS)."
    else
        tc_msg_warn "Xray instalado. Si no inició, revise: journalctl -u xray -n 20"
    fi
    tc_pause
}

# ── Añadir Cuenta Universal (VMess + VLESS) ───────────────────
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

    # 2. UUID Único
    uuid="$(tc_gen_uuid)"

    # 3. Días de validez
    printf '%bDías de duración [Enter = 30 días]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r days
    [[ -z "$days" ]] && days="30"
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        tc_msg_warn "Días inválidos. Asignando 30 días por defecto."
        days=30
    fi
    expiry_date="$(date -d "+${days} days" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)"

    # 4. Inyectar UUID en todos los inbounds de config.json
    local tmp_json="${TC_XRAY_CONF}.tmp"
    jq --arg id "$uuid" '
      .inbounds |= map(
        if .protocol == "vmess" then
          .settings.clients += [{"id": $id, "alterId": 0}]
        elif .protocol == "vless" then
          .settings.clients += [{"id": $id, "level": 0}]
        else
          .
        end
      )
    ' "$TC_XRAY_CONF" > "$tmp_json" && mv "$tmp_json" "$TC_XRAY_CONF"

    mkdir -p "$TC_XRAY_DIR"
    echo "${nick} | ${uuid} | ${expiry_date} | $(date +%Y-%m-%d)" >> "$TC_XRAY_USERS"

    tc_xray_restart_service >/dev/null 2>&1

    tc_clear
    tc_title "CUENTA CREADA CON ÉXITO"
    tc_xray_show_user_links "$nick" "$uuid"
    tc_pause
}

# ── Modificar UUID de una cuenta ──────────────────────────────
tc_xray_modify_uuid() {
    tc_clear
    tc_title "MODIFICAR UUID DE UNA CUENTA"

    if [[ ! -f "$TC_XRAY_USERS" || ! -s "$TC_XRAY_USERS" ]]; then
        tc_msg_warn "No hay cuentas de Xray registradas."
        tc_pause
        return
    fi

    local users_arr=() uuids_arr=() exps_arr=()
    local idx=1
    printf '%b%-4s %-16s %-38s %s%b\n' "$TC_YELLOW" "NUM" "USUARIO" "UUID ACTUAL" "EXPIRA" "$TC_NC"
    tc_line

    while IFS='|' read -r u_nick u_uuid u_exp u_created; do
        u_nick="$(echo "$u_nick" | tr -d ' ')"
        u_uuid="$(echo "$u_uuid" | tr -d ' ')"
        u_exp="$(echo "$u_exp" | tr -d ' ')"
        [[ -z "$u_nick" || -z "$u_uuid" ]] && continue

        users_arr+=("$u_nick")
        uuids_arr+=("$u_uuid")
        exps_arr+=("$u_exp")

        printf '%b[%02d]%b > %b%-16s%b %b%-38s%b %s\n' \
            "$TC_GREEN" "$idx" "$TC_NC" \
            "$TC_WHITE" "$u_nick" "$TC_NC" \
            "$TC_PALE_GOLD" "$u_uuid" "$TC_NC" \
            "$u_exp"
        ((idx++))
    done < "$TC_XRAY_USERS"

    if [[ ${#users_arr[@]} -eq 0 ]]; then
        tc_msg_warn "No hay cuentas válidas disponibles."
        tc_pause
        return
    fi

    tc_line
    tc_opt "0" "$(_t 'cancel')"
    tc_line
    tc_prompt "Seleccione cuenta para modificar su UUID"
    read -r sel

    [[ "$sel" == "0" || -z "$sel" ]] && return

    if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#users_arr[@]} )); then
        tc_msg_err "Opción no válida."
        tc_pause
        return
    fi

    local sel_idx=$((sel - 1))
    local sel_user="${users_arr[$sel_idx]}"
    local old_uuid="${uuids_arr[$sel_idx]}"

    printf '\n%bUsuario seleccionado:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$sel_user" "$TC_NC"
    printf '%bUUID Actual         :%b %b%s%b\n\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "$old_uuid" "$TC_NC"

    printf '%bNuevo UUID (Enter para generar automáticamente):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r new_uuid
    [[ -z "$new_uuid" ]] && new_uuid="$(tc_gen_uuid)"

    if ! [[ "$new_uuid" =~ ^[a-f0-9-]{36}$ ]]; then
        tc_msg_err "Formato de UUID inválido."
        tc_pause
        return
    fi

    local tmp_json="${TC_XRAY_CONF}.tmp"
    jq --arg old "$old_uuid" --arg new "$new_uuid" '
      .inbounds |= map(
        if ((.settings.clients? | type) == "array") then
          .settings.clients |= map(if .id == $old then .id = $new else . end)
        else
          .
        end
      )
    ' "$TC_XRAY_CONF" > "$tmp_json" && mv "$tmp_json" "$TC_XRAY_CONF"

    sed -i "s/${old_uuid}/${new_uuid}/g" "$TC_XRAY_USERS"
    tc_xray_restart_service >/dev/null 2>&1

    tc_clear
    tc_title "UUID MODIFICADO CON ÉXITO"
    tc_msg_ok "Nuevo UUID asignado a '$sel_user': $new_uuid"
    tc_xray_show_user_links "$sel_user" "$new_uuid"
    tc_pause
}

# ── Modificar Path WebSocket ──────────────────────────────────
tc_xray_change_path() {
    tc_clear
    tc_title "MODIFICAR PATH WEBSOCKET"

    local cur_path
    cur_path="$(cat "$TC_XRAY_PATH_FILE" 2>/dev/null || echo "/tunnelcore")"
    printf '%bPath actual:%b %b%s%b\n\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$cur_path" "$TC_NC"

    printf '%bNuevo Path WebSocket [Ej: /I6yTCpo4/]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r new_path
    [[ -z "$new_path" ]] && return
    [[ "$new_path" != /* ]] && new_path="/$new_path"

    local tmp_json="${TC_XRAY_CONF}.tmp"
    jq --arg p "$new_path" '
      .inbounds |= map(
        if .streamSettings.wsSettings? then
          .streamSettings.wsSettings.path = $p
        else
          .
        end
      )
    ' "$TC_XRAY_CONF" > "$tmp_json" && mv "$tmp_json" "$TC_XRAY_CONF"

    echo "$new_path" > "$TC_XRAY_PATH_FILE"
    tc_xray_restart_service >/dev/null 2>&1

    tc_msg_ok "Path WebSocket actualizado a: $new_path"
    tc_pause
}

# ── Cambiar Dominio / SNI por defecto ─────────────────────────
tc_xray_change_domain() {
    tc_clear
    tc_title "CAMBIAR DOMINIO / SNI POR DEFECTO"

    local cur_dom
    cur_dom="$(cat "$TC_XRAY_DOMAIN_FILE" 2>/dev/null || tc_public_ip)"
    printf '%bDominio / Host actual:%b %b%s%b\n\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$cur_dom" "$TC_NC"

    printf '%bNuevo Dominio o IP pública:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r new_dom
    if [[ -n "$new_dom" ]]; then
        echo "$new_dom" > "$TC_XRAY_DOMAIN_FILE"
        tc_msg_ok "Dominio / Host actualizado a: $new_dom"
    fi
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

    local users_arr=() uuids_arr=()
    local idx=1
    printf '%b%-4s %-16s %-38s %s%b\n' "$TC_YELLOW" "NUM" "USUARIO" "UUID" "EXPIRA" "$TC_NC"
    tc_line

    while IFS='|' read -r u_nick u_uuid u_exp u_created; do
        u_nick="$(echo "$u_nick" | tr -d ' ')"
        u_uuid="$(echo "$u_uuid" | tr -d ' ')"
        u_exp="$(echo "$u_exp" | tr -d ' ')"
        [[ -z "$u_nick" || -z "$u_uuid" ]] && continue

        users_arr+=("$u_nick")
        uuids_arr+=("$u_uuid")

        printf '%b[%02d]%b > %b%-16s%b %b%-38s%b %s\n' \
            "$TC_GREEN" "$idx" "$TC_NC" \
            "$TC_WHITE" "$u_nick" "$TC_NC" \
            "$TC_PALE_GOLD" "$u_uuid" "$TC_NC" \
            "$u_exp"
        ((idx++))
    done < "$TC_XRAY_USERS"

    tc_line
    printf '%bSeleccione un número para ver sus enlaces URI (o 0 para salir):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r sel
    [[ "$sel" == "0" || -z "$sel" ]] && return

    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#users_arr[@]} )); then
        local s_idx=$((sel - 1))
        tc_clear
        tc_title "ENLACES DE CONEXIÓN"
        tc_xray_show_user_links "${users_arr[$s_idx]}" "${uuids_arr[$s_idx]}"
        tc_pause
    fi
}

# ── Eliminar cuenta Xray ──────────────────────────────────────
tc_xray_del_user() {
    tc_clear
    tc_title "ELIMINAR CUENTA V2RAY"

    if [[ ! -f "$TC_XRAY_USERS" || ! -s "$TC_XRAY_USERS" ]]; then
        tc_msg_warn "No hay cuentas para eliminar."
        tc_pause
        return
    fi

    local users_arr=() uuids_arr=()
    local idx=1
    printf '%b%-4s %-20s %s%b\n' "$TC_YELLOW" "NUM" "USUARIO" "UUID" "$TC_NC"
    tc_line

    while IFS='|' read -r u_nick u_uuid u_exp u_created; do
        u_nick="$(echo "$u_nick" | tr -d ' ')"
        u_uuid="$(echo "$u_uuid" | tr -d ' ')"
        [[ -z "$u_nick" || -z "$u_uuid" ]] && continue

        users_arr+=("$u_nick")
        uuids_arr+=("$u_uuid")

        printf '%b[%02d]%b > %b%-20s%b %s\n' \
            "$TC_RED" "$idx" "$TC_NC" \
            "$TC_WHITE" "$u_nick" "$TC_NC" \
            "$u_uuid"
        ((idx++))
    done < "$TC_XRAY_USERS"

    tc_line
    tc_opt "0" "$(_t 'cancel')"
    tc_line
    tc_prompt "Seleccione cuenta a eliminar"
    read -r sel

    [[ "$sel" == "0" || -z "$sel" ]] && return

    if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#users_arr[@]} )); then
        tc_msg_err "Opción no válida."
        tc_pause
        return
    fi

    local sel_idx=$((sel - 1))
    local target_nick="${users_arr[$sel_idx]}"
    local target_uuid="${uuids_arr[$sel_idx]}"

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
    tc_xray_restart_service >/dev/null 2>&1

    tc_msg_ok "Cuenta '$target_nick' eliminada."
    tc_pause
}

# ── Menú Principal V2Ray / Xray ───────────────────────────────
tc_xray_menu() {
    while true; do
        tc_clear
        tc_title "GESTIÓN DE V2RAY / XRAY $(tc_xray_status_mark)"

        if ! tc_xray_is_installed; then
            tc_opt "1" "INSTALAR V2RAY / XRAY (443 TLS + 80 HTTP + VLESS)"
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
            local cur_dom cur_path
            cur_dom="$(cat "$TC_XRAY_DOMAIN_FILE" 2>/dev/null || echo "No configurado")"
            cur_path="$(cat "$TC_XRAY_PATH_FILE" 2>/dev/null || echo "/tunnelcore")"

            printf '%bPUERTOS ACTIVOS:%b %b443 (TLS WS)%b | %b80 (HTTP WS)%b | %b8443 (VLESS)%b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$TC_NC" "$TC_CYAN" "$TC_NC" "$TC_PALE_GOLD" "$TC_NC"
            printf '%bPATH WEBSOCKET :%b %b%s%b  %bDOMINIO/HOST:%b %b%s%b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$cur_path" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$cur_dom" "$TC_NC"
            tc_line
            tc_opt "1" "AÑADIR CUENTA (GENERA ENLACES 443 TLS Y 80 HTTP)"
            tc_opt "2" "LISTAR CUENTAS / VER ENLACES URI"
            tc_opt "3" "MODIFICAR UUID DE UNA CUENTA"
            tc_opt "4" "CAMBIAR PATH WEBSOCKET"
            tc_opt "5" "CAMBIAR DOMINIO / SNI POR DEFECTO"
            tc_opt "6" "ELIMINAR CUENTA"
            tc_line
            tc_opt "7" "REINICIAR SERVICIO V2RAY"
            tc_opt "8" "VER LOGS EN TIEMPO REAL"
            tc_opt "9" "REINSTALAR / RESTABLECER CONFIGURACIÓN"
            tc_opt "10" "DESINSTALAR V2RAY COMPLETAMENTE"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt

            case "$opt" in
                1|01) tc_xray_add_user ;;
                2|02) tc_xray_list_users ;;
                3|03) tc_xray_modify_uuid ;;
                4|04) tc_xray_change_path ;;
                5|05) tc_xray_change_domain ;;
                6|06) tc_xray_del_user ;;
                7|07)
                    tc_xray_restart_service >/dev/null 2>&1
                    tc_msg_ok "Servicio V2Ray reiniciado."
                    tc_pause
                    ;;
                8|08)
                    tc_clear
                    tc_title "LOGS V2RAY EN VIVO (Ctrl+C para salir)"
                    journalctl -u xray -f --no-pager
                    ;;
                9|09)
                    tc_xray_install
                    ;;
                10)
                    if tc_confirm "¿Está seguro de desinstalar V2Ray / Xray por completo?"; then
                        systemctl stop xray >/dev/null 2>&1 || true
                        systemctl disable xray >/dev/null 2>&1 || true
                        rm -f "$TC_XRAY_SERVICE" "$TC_XRAY_BIN"
                        rm -rf "$TC_XRAY_DIR"
                        systemctl daemon-reload >/dev/null 2>&1 || true
                        tc_msg_ok "V2Ray desinstalado completamente."
                        tc_pause
                    fi
                    ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        fi
    done
}
