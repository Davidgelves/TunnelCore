#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/v2ray.sh
#  Gestor Avanzado de V2Ray / Xray estilo Rufus (Multi-TLS / WS)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_XRAY_DIR="/etc/tunnelcore/v2ray"
TC_XRAY_CONF="${TC_XRAY_DIR}/config.json"
TC_XRAY_USERS="${TC_XRAY_DIR}/users.db"
TC_XRAY_ENV="${TC_XRAY_DIR}/v2ray.env"
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

tc_xray_load_env() {
    V2_HTTP_PORT="80"
    V2_TLS_PORT="443"
    V2_PATH="/tunnelcore"
    V2_DOMAIN=""
    V2_SNI=""
    if [[ -f "$TC_XRAY_ENV" ]]; then
        # shellcheck disable=SC1090
        . "$TC_XRAY_ENV"
    fi
}

tc_xray_save_env() {
    mkdir -p "$TC_XRAY_DIR"
    cat > "$TC_XRAY_ENV" <<EOF
V2_HTTP_PORT="${V2_HTTP_PORT:-80}"
V2_TLS_PORT="${V2_TLS_PORT:-443}"
V2_PATH="${V2_PATH:-/tunnelcore}"
V2_DOMAIN="${V2_DOMAIN:-}"
V2_SNI="${V2_SNI:-}"
EOF
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

# ── Generar config base multi-puerto (HTTP 80 + TLS 443 + VMess/VLESS) ──
tc_xray_write_base_config() {
    tc_xray_load_env
    tc_xray_ensure_certs

    local http_p="${V2_HTTP_PORT:-80}"
    local tls_p="${V2_TLS_PORT:-443}"
    local path="${V2_PATH:-/tunnelcore}"
    local init_uuid
    init_uuid="$(tc_gen_uuid)"

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
      "tag": "vmess-ws-http",
      "port": ${http_p},
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
      "tag": "vless-ws-http",
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
    },
    {
      "tag": "vmess-ws-tls",
      "port": ${tls_p},
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

    echo "admin | ${init_uuid} | $(date '+%Y-%m-%d' -d '+365 days' 2>/dev/null || echo '2030-01-01')" > "$TC_XRAY_USERS"
    chmod 600 "$TC_XRAY_CONF" "$TC_XRAY_USERS"
}

# ── Instalar V2Ray estilo Rufus ───────────────────────────────
tc_xray_install() {
    tc_clear
    tc_title "INSTALADOR V2RAY / XRAY (ESTILO RUFUS)"

    local http_p tls_p path domain sni

    printf '%bPuerto HTTP sin TLS (WebSocket) [Enter = 80]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r http_p
    [[ -z "$http_p" ]] && http_p="80"

    printf '%bPuerto HTTPS con TLS (WebSocket) [Enter = 443]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r tls_p
    [[ -z "$tls_p" ]] && tls_p="443"

    printf '%bPath WebSocket [Enter = /tunnelcore]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r path
    [[ -z "$path" ]] && path="/tunnelcore"
    [[ "$path" != /* ]] && path="/$path"

    printf '%bDominio / Host CDN (opcional, ej: midominio.com):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r domain

    V2_HTTP_PORT="$http_p"
    V2_TLS_PORT="$tls_p"
    V2_PATH="$path"
    V2_DOMAIN="$domain"
    V2_SNI="$domain"
    tc_xray_save_env

    tc_xray_install_binary || {
        tc_msg_err "Falló la instalación de Xray."
        tc_pause
        return 1
    }

    tc_xray_write_base_config
    systemctl restart xray >/dev/null 2>&1

    if tc_xray_is_running; then
        tc_msg_ok "¡V2Ray instalado y activo en puertos $http_p (HTTP) y $tls_p (TLS)!"
    else
        tc_msg_warn "V2Ray instalado. Verifique el estado con journalctl -u xray."
    fi
    tc_pause
}

# ── Añadir cuenta V2Ray Universal ─────────────────────────────
tc_xray_add_user() {
    if ! tc_xray_is_installed; then
        tc_msg_warn "V2Ray no está instalado. Instálelo primero."
        tc_pause
        return
    fi

    tc_clear
    tc_title "AGREGAR USUARIO V2RAY (ESTILO RUFUS)"
    tc_xray_load_env

    local nick uuid days expiry_date

    while true; do
        printf '%bNombre / Nickname del usuario:%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r nick
        nick="$(echo "$nick" | tr -d ' ')"
        [[ -z "$nick" ]] && { tc_msg_err "El nombre no puede estar vacío."; continue; }
        if grep -qE "^[[:space:]]*${nick}[[:space:]]*\|" "$TC_XRAY_USERS" 2>/dev/null; then
            tc_msg_err "Ya existe un usuario con ese nombre."
            continue
        fi
        break
    done

    printf '%bUUID personalizado (Enter para generar automático):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r uuid
    [[ -z "$uuid" ]] && uuid="$(tc_gen_uuid)"

    printf '%bDuración de la cuenta en días [1-365] (Enter = 30):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r days
    [[ -z "$days" ]] && days="30"
    expiry_date="$(date '+%Y-%m-%d' -d "+${days} days" 2>/dev/null || echo "2030-01-01")"

    # Insertar en todos los inbounds de config.json
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

    echo "${nick} | ${uuid} | ${expiry_date}" >> "$TC_XRAY_USERS"
    systemctl restart xray >/dev/null 2>&1

    # Generar Enlaces URI
    local vps_ip host_cdn sni_host path_ws
    vps_ip="$(tc_public_ip)"
    host_cdn="${V2_DOMAIN:-$vps_ip}"
    sni_host="${V2_SNI:-$host_cdn}"
    path_ws="${V2_PATH:-/tunnelcore}"

    # 1. VMess TLS 443 (Cloudflare / SNI)
    local vmess_tls_json b64_tls uri_vmess_tls
    vmess_tls_json=$(cat <<EOF
{"v":"2","ps":"${nick}-TLS443","add":"${host_cdn}","port":"${V2_TLS_PORT:-443}","id":"${uuid}","aid":"0","scy":"auto","net":"ws","type":"none","host":"${host_cdn}","path":"${path_ws}","tls":"tls","sni":"${sni_host}","alpn":"","fp":""}
EOF
)
    b64_tls="$(printf '%s' "$vmess_tls_json" | base64 | tr -d '\n\r ')"
    uri_vmess_tls="vmess://${b64_tls}"

    # 2. VMess HTTP 80 (Sin TLS / Directo)
    local vmess_http_json b64_http uri_vmess_http
    vmess_http_json=$(cat <<EOF
{"v":"2","ps":"${nick}-HTTP80","add":"${vps_ip}","port":"${V2_HTTP_PORT:-80}","id":"${uuid}","aid":"0","scy":"auto","net":"ws","type":"none","host":"","path":"${path_ws}","tls":"none","sni":"","alpn":"","fp":""}
EOF
)
    b64_http="$(printf '%s' "$vmess_http_json" | base64 | tr -d '\n\r ')"
    uri_vmess_http="vmess://${b64_http}"

    # 3. VLESS TLS 443
    local enc_path uri_vless_tls
    enc_path="$(printf '%s' "$path_ws" | sed 's/\//%2F/g')"
    uri_vless_tls="vless://${uuid}@${host_cdn}:${V2_TLS_PORT:-443}?type=ws&security=tls&sni=${sni_host}&host=${host_cdn}&path=${enc_path}#${nick}-VLESS-TLS"

    tc_clear
    tc_title "CUENTA V2RAY CREADA CON ÉXITO"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "USUARIO:" "$TC_NC" "$TC_WHITE" "$nick" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "UUID:" "$TC_NC" "$TC_WHITE" "$uuid" "$TC_NC"
    printf '%b%-20s%b %b%s (%s días)%b\n' "$TC_DARK_GREEN" "EXPIRA:" "$TC_NC" "$TC_WHITE" "$expiry_date" "$days" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "PATH WS:" "$TC_NC" "$TC_WHITE" "$path_ws" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "HOST / DOMINIO:" "$TC_NC" "$TC_WHITE" "$host_cdn" "$TC_NC"
    tc_line
    printf '%b[1] ENLACE VMESS CON TLS (PUERTO %s / CLOUDFLARE / SNI):%b\n' "$TC_YELLOW" "${V2_TLS_PORT:-443}" "$TC_NC"
    printf '%b%s%b\n\n' "$TC_CYAN" "$uri_vmess_tls" "$TC_NC"
    printf '%b[2] ENLACE VMESS SIN TLS (PUERTO %s / DIRECTO IP):%b\n' "$TC_YELLOW" "${V2_HTTP_PORT:-80}" "$TC_NC"
    printf '%b%s%b\n\n' "$TC_CYAN" "$uri_vmess_http" "$TC_NC"
    printf '%b[3] ENLACE VLESS CON TLS (PUERTO %s):%b\n' "$TC_YELLOW" "${V2_TLS_PORT:-443}" "$TC_NC"
    printf '%b%s%b\n' "$TC_CYAN" "$uri_vless_tls" "$TC_NC"
    tc_line
    tc_pause
}

# ── Renovar Días de Usuario ───────────────────────────────────
tc_xray_renew_user() {
    tc_clear
    tc_title "RENOVAR DÍAS DE USUARIO V2RAY"

    if [[ ! -f "$TC_XRAY_USERS" || ! -s "$TC_XRAY_USERS" ]]; then
        tc_msg_warn "No hay usuarios registrados."
        tc_pause
        return
    fi

    local -a users_arr=() uuids_arr=() exps_arr=()
    local idx=0
    while IFS='|' read -r nick uuid exp || [[ -n "$nick" ]]; do
        nick="$(echo "$nick" | tr -d ' ')"
        uuid="$(echo "$uuid" | tr -d ' ')"
        exp="$(echo "$exp" | tr -d ' ')"
        [[ -z "$nick" ]] && continue
        users_arr+=("$nick")
        uuids_arr+=("$uuid")
        exps_arr+=("$exp")
        idx=$((idx + 1))
        tc_opt "$idx" "${nick} (Expira: ${exp})"
    done < "$TC_XRAY_USERS"

    tc_line
    tc_opt "0" "$(_t 'cancel')"
    tc_line
    tc_prompt "Seleccione usuario a renovar"
    read -r sel

    [[ "$sel" == "0" || -z "$sel" ]] && return

    if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#users_arr[@]} )); then
        tc_msg_err "Opción no válida."
        tc_pause
        return
    fi

    local sel_idx=$((sel - 1))
    local sel_user="${users_arr[$sel_idx]}"
    local sel_uuid="${uuids_arr[$sel_idx]}"
    local sel_exp="${exps_arr[$sel_idx]}"

    printf '\n%bUsuario:%b %b%s%b  %bExpiración actual:%b %b%s%b\n' \
        "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$sel_user" "$TC_NC" \
        "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "$sel_exp" "$TC_NC"

    printf '%bDías a añadir [1-365] (Enter = 30):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r add_d
    [[ -z "$add_d" ]] && add_d="30"

    local new_exp
    new_exp="$(date '+%Y-%m-%d' -d "${sel_exp} +${add_d} days" 2>/dev/null || date '+%Y-%m-%d' -d "+${add_d} days")"

    sed -i "/^[[:space:]]*${sel_user}[[:space:]]*|/d" "$TC_XRAY_USERS"
    echo "${sel_user} | ${sel_uuid} | ${new_exp}" >> "$TC_XRAY_USERS"

    tc_msg_ok "¡Usuario '$sel_user' renovado exitosamente hasta el $new_exp!"
    tc_pause
}

# ── Modificar UUID de Cuenta ──────────────────────────────────
tc_xray_modify_uuid() {
    tc_clear
    tc_title "MODIFICAR UUID DE USUARIO V2RAY"

    if [[ ! -f "$TC_XRAY_USERS" || ! -s "$TC_XRAY_USERS" ]]; then
        tc_msg_warn "No hay usuarios registrados."
        tc_pause
        return
    fi

    local -a users_arr=() uuids_arr=() exps_arr=()
    local idx=0
    while IFS='|' read -r nick uuid exp || [[ -n "$nick" ]]; do
        nick="$(echo "$nick" | tr -d ' ')"
        uuid="$(echo "$uuid" | tr -d ' ')"
        exp="$(echo "$exp" | tr -d ' ')"
        [[ -z "$nick" ]] && continue
        users_arr+=("$nick")
        uuids_arr+=("$uuid")
        exps_arr+=("$exp")
        idx=$((idx + 1))
        tc_opt "$idx" "${nick} (${uuid})"
    done < "$TC_XRAY_USERS"

    tc_line
    tc_opt "0" "$(_t 'cancel')"
    tc_line
    tc_prompt "Seleccione usuario para modificar UUID"
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

    printf '\n%bUsuario:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$sel_user" "$TC_NC"
    printf '%bUUID Actual:%b %b%s%b\n\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "$old_uuid" "$TC_NC"

    printf '%bNuevo UUID (Enter para generar automático):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r new_uuid
    [[ -z "$new_uuid" ]] && new_uuid="$(tc_gen_uuid)"

    if ! [[ "$new_uuid" =~ ^[a-f0-9-]{36}$ ]]; then
        tc_msg_err "Formato de UUID no válido."
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
    systemctl restart xray >/dev/null 2>&1

    tc_msg_ok "UUID actualizado correctamente."
    printf '%bNuevo UUID:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$new_uuid" "$TC_NC"
    tc_pause
}

# ── Configurar Dominio y Certificado TLS ──────────────────────
tc_xray_config_tls() {
    tc_clear
    tc_title "CONFIGURAR DOMINIO Y CERTIFICADO TLS"
    tc_xray_load_env

    printf '%bDominio / Host actual:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${V2_DOMAIN:-No configurado}" "$TC_NC"
    printf '%bSNI / Bug actual:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${V2_SNI:-No configurado}" "$TC_NC"
    tc_line

    printf '%bNuevo Dominio CDN / Host:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r new_dom
    [[ -n "$new_dom" ]] && V2_DOMAIN="$new_dom"

    printf '%bNuevo SNI / Bug Host [Enter para usar %s]:%b ' "$TC_DARK_GREEN" "${V2_DOMAIN:-$new_dom}" "$TC_NC"
    read -r new_sni
    [[ -n "$new_sni" ]] && V2_SNI="$new_sni" || V2_SNI="$V2_DOMAIN"

    tc_xray_save_env
    tc_xray_ensure_certs
    systemctl restart xray >/dev/null 2>&1

    tc_msg_ok "Dominio y parámetros TLS actualizados."
    tc_pause
}

# ── Listar Usuarios ───────────────────────────────────────────
tc_xray_list_users() {
    tc_clear
    tc_title "USUARIOS V2RAY REGISTRADOS"

    if [[ ! -f "$TC_XRAY_USERS" || ! -s "$TC_XRAY_USERS" ]]; then
        tc_msg_warn "No hay cuentas registradas."
        tc_pause
        return
    fi

    printf '%b%-16s %-38s %-12s%b\n' "$TC_YELLOW" "USUARIO" "UUID" "EXPIRA" "$TC_NC"
    tc_line

    local nick uuid exp
    while IFS='|' read -r nick uuid exp || [[ -n "$nick" ]]; do
        nick="$(echo "$nick" | tr -d ' ')"
        uuid="$(echo "$uuid" | tr -d ' ')"
        exp="$(echo "$exp" | tr -d ' ')"
        [[ -z "$nick" ]] && continue
        printf '%b%-16s%b %b%-38s%b %b%-12s%b\n' \
            "$TC_WHITE" "$nick" "$TC_NC" \
            "$TC_DARK_GREEN" "$uuid" "$TC_NC" \
            "$TC_PALE_GOLD" "$exp" "$TC_NC"
    done < "$TC_XRAY_USERS"

    tc_line
    tc_pause
}

# ── Eliminar Usuario ──────────────────────────────────────────
tc_xray_del_user() {
    tc_clear
    tc_title "ELIMINAR USUARIO V2RAY"

    if [[ ! -f "$TC_XRAY_USERS" || ! -s "$TC_XRAY_USERS" ]]; then
        tc_msg_warn "No hay usuarios para eliminar."
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

    if ! tc_confirm "¿Eliminar al usuario '$target_nick' ($target_uuid)?"; then
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

    tc_msg_ok "Usuario '$target_nick' eliminado."
    tc_pause
}

# ── Menú Principal V2Ray / Xray estilo Rufus ──────────────────
tc_xray_menu() {
    while true; do
        tc_clear
        tc_xray_load_env
        tc_title "GESTIÓN DE V2RAY / XRAY $(tc_xray_status_mark)"

        if ! tc_xray_is_installed; then
            tc_opt "1" "INSTALAR V2RAY / XRAY"
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
            printf '%bPUERTOS:%b %bHTTP %s | TLS %s%b  %bPATH:%b %b%s%b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "${V2_HTTP_PORT:-80}" "${V2_TLS_PORT:-443}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${V2_PATH:-/tunnelcore}" "$TC_NC"
            printf '%bDOMINIO / HOST:%b %b%s%b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "${V2_DOMAIN:-No configurado}" "$TC_NC"
            tc_line
            tc_opt "1" "AGREGAR USUARIO (VMESS + VLESS)"
            tc_opt "2" "LISTAR USUARIOS REGISTRADOS"
            tc_opt "3" "RENOVAR DÍAS DE USUARIO"
            tc_opt "4" "MODIFICAR UUID DE USUARIO"
            tc_opt "5" "ELIMINAR USUARIO"
            tc_line
            tc_opt "6" "CONFIGURAR DOMINIO Y CERTIFICADO TLS"
            tc_opt "7" "REINICIAR SERVICIO V2RAY"
            tc_opt "8" "VER LOGS EN TIEMPO REAL"
            tc_opt "9" "REINSTALAR V2RAY"
            tc_opt "10" "DESINSTALAR V2RAY"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt

            case "$opt" in
                1|01) tc_xray_add_user ;;
                2|02) tc_xray_list_users ;;
                3|03) tc_xray_renew_user ;;
                4|04) tc_xray_modify_uuid ;;
                5|05) tc_xray_del_user ;;
                6|06) tc_xray_config_tls ;;
                7|07)
                    systemctl restart xray >/dev/null 2>&1
                    tc_msg_ok "Servicio V2Ray reiniciado."
                    tc_pause
                    ;;
                8|08)
                    tc_clear
                    tc_title "LOGS V2RAY EN VIVO (Ctrl+C para salir)"
                    journalctl -u xray -f --no-pager
                    ;;
                9|09) tc_xray_install ;;
                10)
                    if tc_confirm "¿Está seguro de desinstalar V2Ray por completo?"; then
                        systemctl stop xray >/dev/null 2>&1 || true
                        systemctl disable xray >/dev/null 2>&1 || true
                        rm -f "$TC_XRAY_SERVICE" "$TC_XRAY_BIN"
                        rm -rf "$TC_XRAY_DIR"
                        systemctl daemon-reload >/dev/null 2>&1 || true
                        tc_msg_ok "V2Ray desinstalado."
                        tc_pause
                    fi
                    ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        fi
    done
}
