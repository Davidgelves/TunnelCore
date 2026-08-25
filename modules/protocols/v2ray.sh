#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/v2ray.sh
#  Gestor de V2Ray / Xray Oficial (Configuración desde Cero)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_V2_DIR="/etc/tunnelcore/v2ray"
TC_V2_CONF="${TC_V2_DIR}/config.json"
TC_V2_REG="${TC_V2_DIR}/users.db"
TC_V2_ENV="${TC_V2_DIR}/v2ray.env"
TC_V2_CERT="${TC_V2_DIR}/server.crt"
TC_V2_KEY="${TC_V2_DIR}/server.key"
TC_V2_BIN="/usr/local/bin/xray"
TC_V2_SERVICE="/etc/systemd/system/xray.service"

# ── Detección de Estado ───────────────────────────────────────
tc_v2_config_file() {
    local cfg
    for cfg in "$TC_V2_CONF" /etc/v2ray/config.json /usr/local/etc/v2ray/config.json /usr/local/etc/xray/config.json /etc/xray/config.json; do
        [[ -f "$cfg" ]] && echo "$cfg" && return 0
    done
    return 1
}

tc_v2_is_installed() {
    [[ -x "$TC_V2_BIN" && -f "$TC_V2_CONF" ]] || command -v v2ray >/dev/null 2>&1
}

tc_v2_is_running() {
    systemctl is-active --quiet xray 2>/dev/null || systemctl is-active --quiet v2ray 2>/dev/null || pgrep -x xray >/dev/null 2>&1 || pgrep -x v2ray >/dev/null 2>&1
}

tc_v2_status_mark() {
    if tc_v2_is_running; then
        printf '%b[ON]%b' "$TC_GREEN" "$TC_NC"
    elif tc_v2_is_installed; then
        printf '%b[OFF]%b' "$TC_RED" "$TC_NC"
    else
        printf '%b[NO INSTALADO]%b' "$TC_YELLOW" "$TC_NC"
    fi
}

tc_v2_load_env() {
    V2_PROTO="multi"
    V2_NETWORK="ws"
    V2_HTTP_PORT="80"
    V2_TLS_PORT="443"
    V2_PATH="/tunnelcore"
    V2_DOMAIN=""
    V2_SNI=""
    if [[ -f "$TC_V2_ENV" ]]; then
        # shellcheck disable=SC1090
        . "$TC_V2_ENV"
    fi
}

tc_v2_save_env() {
    mkdir -p "$TC_V2_DIR"
    cat > "$TC_V2_ENV" <<EOF
V2_PROTO="${V2_PROTO:-multi}"
V2_NETWORK="${V2_NETWORK:-ws}"
V2_HTTP_PORT="${V2_HTTP_PORT:-80}"
V2_TLS_PORT="${V2_TLS_PORT:-443}"
V2_PATH="${V2_PATH:-/tunnelcore}"
V2_DOMAIN="${V2_DOMAIN:-}"
V2_SNI="${V2_SNI:-}"
EOF
}

tc_v2_ensure_certs() {
    mkdir -p "$TC_V2_DIR"
    if [[ ! -f "$TC_V2_CERT" || ! -f "$TC_V2_KEY" ]]; then
        openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
            -keyout "$TC_V2_KEY" -out "$TC_V2_CERT" -subj "/CN=tunnelcore-v2ray" >/dev/null 2>&1 || true
        chmod 600 "$TC_V2_KEY" "$TC_V2_CERT" 2>/dev/null || true
    fi
}

tc_v2_free_conflicts() {
    # Desactivar servidores web residuales que puedan bloquear los puertos 80/443
    systemctl stop apache2 >/dev/null 2>&1 || true
    systemctl disable apache2 >/dev/null 2>&1 || true
    systemctl stop nginx >/dev/null 2>&1 || true
    systemctl disable nginx >/dev/null 2>&1 || true
}

tc_v2_restart() {
    tc_v2_free_conflicts
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable xray >/dev/null 2>&1 || true
    systemctl restart xray >/dev/null 2>&1 || true
    if command -v v2ray >/dev/null 2>&1; then
        v2ray restart >/dev/null 2>&1 || true
    fi
    sleep 0.5
}

# ── Descargar Binario Oficial de V2Ray/Xray Core ───────────────
tc_v2_install_core_bin() {
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
            tc_msg_err "Arquitectura no soportada para V2Ray: $arch"
            return 1
            ;;
    esac

    local xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/${asset}"
    local tmp_dir="/tmp/xray-install-$$"
    mkdir -p "$tmp_dir"

    tc_msg_ok "Descargando núcleo oficial V2Ray ($arch)..."
    if ! curl -fsSL --connect-timeout 5 --max-time 60 -o "${tmp_dir}/xray.zip" "$xray_url"; then
        wget -q --timeout=30 -O "${tmp_dir}/xray.zip" "$xray_url" || {
            tc_msg_err "Error descargando el núcleo V2Ray."
            rm -rf "$tmp_dir"
            return 1
        }
    fi

    unzip -q -o "${tmp_dir}/xray.zip" -d "$tmp_dir" >/dev/null 2>&1 || {
        tc_msg_err "Error al descomprimir el archivo de V2Ray."
        rm -rf "$tmp_dir"
        return 1
    }

    install -m 755 "${tmp_dir}/xray" "$TC_V2_BIN"
    rm -rf "$tmp_dir"

    mkdir -p /usr/local/share/xray /var/log/xray "$TC_V2_DIR" /etc/v2ray
    tc_v2_ensure_certs

    # Servicio systemd
    cat > "$TC_V2_SERVICE" <<EOF
[Unit]
Description=TunnelCore V2Ray/Xray Core Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${TC_V2_BIN} run -config ${TC_V2_CONF}
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

# ── Generador Completo de Configuración desde Cero ────────────
tc_v2_build_config_from_scratch() {
    local http_p="${V2_HTTP_PORT:-80}"
    local tls_p="${V2_TLS_PORT:-443}"
    local path="${V2_PATH:-/tunnelcore}"
    local init_uuid="$(tc_gen_uuid)"

    mkdir -p "$TC_V2_DIR" /var/log/xray
    tc_v2_ensure_certs

    cat > "$TC_V2_CONF" <<EOF
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
              "certificateFile": "${TC_V2_CERT}",
              "keyFile": "${TC_V2_KEY}"
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

    ln -sf "$TC_V2_CONF" /etc/v2ray/config.json 2>/dev/null || true
    echo "admin | ${init_uuid} | $(date '+%Y-%m-%d' -d '+365 days' 2>/dev/null || echo '2030-01-01')" > "$TC_V2_REG"
    chmod 600 "$TC_V2_CONF" "$TC_V2_REG"
}

# ── Instalador y Asistente de Configuración desde Cero ────────
tc_v2_setup_wizard() {
    tc_clear
    tc_title "CONFIGURACIÓN DE V2RAY / XRAY DESDE CERO"

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y curl wget unzip ca-certificates jq uuid-runtime openssl >/dev/null 2>&1 || true
    fi

    # 1. Puerto HTTP (sin TLS)
    printf '%b[1] Puerto HTTP sin TLS (WebSocket) [Enter = 80]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    local http_p
    read -r http_p
    [[ -z "$http_p" ]] && http_p="80"

    # 2. Puerto HTTPS (con TLS)
    printf '%b[2] Puerto HTTPS con TLS (WebSocket) [Enter = 443]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    local tls_p
    read -r tls_p
    [[ -z "$tls_p" ]] && tls_p="443"

    # 3. Path WebSocket
    printf '%b[3] Path WebSocket [Enter = /tunnelcore]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    local path
    read -r path
    [[ -z "$path" ]] && path="/tunnelcore"
    [[ "$path" != /* ]] && path="/$path"

    # 4. Dominio / Host CDN
    printf '%b[4] Dominio CDN / Host Cloudflare (opcional, ej: midominio.com):%b ' "$TC_DARK_GREEN" "$TC_NC"
    local domain
    read -r domain

    local sni="$domain"
    if [[ -n "$domain" ]]; then
        printf '%b[5] SNI / Bug Host [Enter para usar %s]:%b ' "$TC_DARK_GREEN" "$domain" "$TC_NC"
        read -r sni_in
        [[ -n "$sni_in" ]] && sni="$sni_in"
    fi

    V2_PROTO="multi"
    V2_NETWORK="ws"
    V2_HTTP_PORT="$http_p"
    V2_TLS_PORT="$tls_p"
    V2_PATH="$path"
    V2_DOMAIN="$domain"
    V2_SNI="$sni"
    tc_v2_save_env

    tc_v2_install_core_bin || {
        tc_msg_err "Falló la instalación del binario V2Ray."
        tc_pause
        return 1
    }

    tc_v2_build_config_from_scratch
    tc_v2_restart

    if tc_v2_is_running; then
        tc_msg_ok "¡V2Ray configurado e iniciado con éxito [ON]!"
    else
        tc_msg_warn "Iniciando servicio..."
        systemctl start xray >/dev/null 2>&1 || true
        tc_v2_restart
    fi
    tc_pause
}

# ── Agregar Usuario Rápido (Flujo Simple Sin Preguntas Complejas) ──
tc_v2_add_user_simple() {
    if ! tc_v2_is_installed; then
        tc_msg_warn "V2Ray no está instalado. Ejecute la configuración desde cero primero."
        tc_pause
        return
    fi

    tc_clear
    tc_title "AGREGAR USUARIO V2RAY"
    tc_v2_load_env

    local nick
    while true; do
        printf '%bNombre / Alias del usuario:%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r nick
        nick="$(echo "$nick" | tr -d ' ')"
        [[ -z "$nick" ]] && { tc_msg_err "El nombre no puede estar vacío."; continue; }
        if grep -qE "^[[:space:]]*${nick}[[:space:]]*\|" "$TC_V2_REG" 2>/dev/null; then
            tc_msg_err "Ya existe un usuario con ese nombre."
            continue
        fi
        break
    done

    printf '%bDías de duración [1-365] (Enter = 30):%b ' "$TC_DARK_GREEN" "$TC_NC"
    local days
    read -r days
    [[ -z "$days" ]] && days="30"
    local expiry_date="$(date '+%Y-%m-%d' -d "+${days} days" 2>/dev/null || echo "2030-01-01")"

    printf '%bUUID personalizado (Enter para generar aleatorio):%b ' "$TC_DARK_GREEN" "$TC_NC"
    local uuid
    read -r uuid
    [[ -z "$uuid" ]] && uuid="$(tc_gen_uuid)"

    # Insertar UUID en todos los inbounds de config.json
    local tmp="${TC_V2_CONF}.tmp"
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
    ' "$TC_V2_CONF" > "$tmp" && mv "$tmp" "$TC_V2_CONF"

    echo "${nick} | ${uuid} | ${expiry_date}" >> "$TC_V2_REG"
    tc_v2_restart

    # Generar todos los enlaces listos
    local vps_ip="$(tc_public_ip)"
    local host_cdn="${V2_DOMAIN:-$vps_ip}"
    local sni_host="${V2_SNI:-$host_cdn}"
    local path_ws="${V2_PATH:-/tunnelcore}"
    local http_p="${V2_HTTP_PORT:-80}"
    local tls_p="${V2_TLS_PORT:-443}"

    # 1. VMess TLS (Puerto 443 / Cloudflare CDN)
    local vmess_tls_json b64_tls uri_vmess_tls
    vmess_tls_json=$(cat <<EOF
{"v":"2","ps":"${nick}-TLS","add":"${host_cdn}","port":"${tls_p}","id":"${uuid}","aid":"0","scy":"auto","net":"ws","type":"none","host":"${host_cdn}","path":"${path_ws}","tls":"tls","sni":"${sni_host}","alpn":"","fp":""}
EOF
)
    b64_tls="$(printf '%s' "$vmess_tls_json" | base64 | tr -d '\n\r ')"
    uri_vmess_tls="vmess://${b64_tls}"

    # 2. VMess Directo IP (Puerto 80 / Sin TLS)
    local vmess_http_json b64_http uri_vmess_http
    vmess_http_json=$(cat <<EOF
{"v":"2","ps":"${nick}-HTTP","add":"${vps_ip}","port":"${http_p}","id":"${uuid}","aid":"0","scy":"auto","net":"ws","type":"none","host":"","path":"${path_ws}","tls":"none","sni":"","alpn":"","fp":""}
EOF
)
    b64_http="$(printf '%s' "$vmess_http_json" | base64 | tr -d '\n\r ')"
    uri_vmess_http="vmess://${b64_http}"

    # 3. VLESS TLS
    local enc_path="$(printf '%s' "$path_ws" | sed 's/\//%2F/g')"
    local uri_vless_tls="vless://${uuid}@${host_cdn}:${tls_p}?type=ws&security=tls&sni=${sni_host}&host=${host_cdn}&path=${enc_path}#${nick}-VLESS"

    tc_clear
    tc_title "CUENTA V2RAY CREADA CON ÉXITO"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "USUARIO:" "$TC_NC" "$TC_WHITE" "$nick" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "UUID:" "$TC_NC" "$TC_WHITE" "$uuid" "$TC_NC"
    printf '%b%-20s%b %b%s (%s días)%b\n' "$TC_DARK_GREEN" "EXPIRA:" "$TC_NC" "$TC_WHITE" "$expiry_date" "$days" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "PATH WS:" "$TC_NC" "$TC_WHITE" "$path_ws" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "HOST CDN / DOMINIO:" "$TC_NC" "$TC_WHITE" "$host_cdn" "$TC_NC"
    tc_line
    printf '%b[1] ENLACE VMESS CON TLS (PUERTO %s / CLOUDFLARE / SNI):%b\n' "$TC_YELLOW" "$tls_p" "$TC_NC"
    printf '%b%s%b\n\n' "$TC_CYAN" "$uri_vmess_tls" "$TC_NC"
    printf '%b[2] ENLACE VMESS SIN TLS (PUERTO %s / DIRECTO IP):%b\n' "$TC_YELLOW" "$http_p" "$TC_NC"
    printf '%b%s%b\n\n' "$TC_CYAN" "$uri_vmess_http" "$TC_NC"
    printf '%b[3] ENLACE VLESS CON TLS (PUERTO %s):%b\n' "$TC_YELLOW" "$tls_p" "$TC_NC"
    printf '%b%s%b\n' "$TC_CYAN" "$uri_vless_tls" "$TC_NC"
    tc_line
    tc_pause
}

# ── Listar Usuarios ───────────────────────────────────────────
tc_v2_list_users() {
    tc_clear
    tc_title "USUARIOS V2RAY REGISTRADOS"

    if [[ ! -f "$TC_V2_REG" || ! -s "$TC_V2_REG" ]]; then
        tc_msg_warn "No hay usuarios registrados."
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
    done < "$TC_V2_REG"

    tc_line
    tc_pause
}

# ── Renovar Días de Usuario ───────────────────────────────────
tc_v2_renew_user() {
    tc_clear
    tc_title "RENOVAR DÍAS DE USUARIO V2RAY"

    if [[ ! -f "$TC_V2_REG" || ! -s "$TC_V2_REG" ]]; then
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
    done < "$TC_V2_REG"

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

    sed -i "/^[[:space:]]*${sel_user}[[:space:]]*|/d" "$TC_V2_REG"
    echo "${sel_user} | ${sel_uuid} | ${new_exp}" >> "$TC_V2_REG"

    tc_msg_ok "¡Usuario '$sel_user' renovado hasta el $new_exp!"
    tc_pause
}

# ── Modificar UUID ────────────────────────────────────────────
tc_v2_modify_uuid() {
    tc_clear
    tc_title "MODIFICAR UUID V2RAY"

    if [[ ! -f "$TC_V2_REG" || ! -s "$TC_V2_REG" ]]; then
        tc_msg_warn "No hay usuarios registrados."
        tc_pause
        return
    fi

    local -a users_arr=() uuids_arr=()
    local idx=0
    while IFS='|' read -r nick uuid exp || [[ -n "$nick" ]]; do
        nick="$(echo "$nick" | tr -d ' ')"
        uuid="$(echo "$uuid" | tr -d ' ')"
        exp="$(echo "$exp" | tr -d ' ')"
        [[ -z "$nick" ]] && continue
        users_arr+=("$nick")
        uuids_arr+=("$uuid")
        idx=$((idx + 1))
        tc_opt "$idx" "${nick} (${uuid})"
    done < "$TC_V2_REG"

    tc_line
    tc_opt "0" "$(_t 'cancel')"
    tc_line
    tc_prompt "Seleccione usuario"
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

    local tmp="${TC_V2_CONF}.tmp"
    jq --arg old "$old_uuid" --arg new "$new_uuid" '
      .inbounds |= map(
        if ((.settings.clients? | type) == "array") then
          .settings.clients |= map(if .id == $old then .id = $new else . end)
        else
          .
        end
      )
    ' "$TC_V2_CONF" > "$tmp" && mv "$tmp" "$TC_V2_CONF"

    sed -i "s/${old_uuid}/${new_uuid}/g" "$TC_V2_REG"
    tc_v2_restart

    tc_msg_ok "UUID modificado correctamente."
    printf '%bNuevo UUID:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$new_uuid" "$TC_NC"
    tc_pause
}

# ── Eliminar Usuario ──────────────────────────────────────────
tc_v2_del_user() {
    tc_clear
    tc_title "ELIMINAR USUARIO V2RAY"

    if [[ ! -f "$TC_V2_REG" || ! -s "$TC_V2_REG" ]]; then
        tc_msg_warn "No hay usuarios registrados."
        tc_pause
        return
    fi

    local -a users_arr=() uuids_arr=()
    local idx=0
    while IFS='|' read -r nick uuid exp || [[ -n "$nick" ]]; do
        nick="$(echo "$nick" | tr -d ' ')"
        uuid="$(echo "$uuid" | tr -d ' ')"
        [[ -z "$nick" ]] && continue
        users_arr+=("$nick")
        uuids_arr+=("$uuid")
        idx=$((idx + 1))
        tc_opt "$idx" "${nick}"
    done < "$TC_V2_REG"

    tc_line
    tc_opt "0" "$(_t 'cancel')"
    tc_line
    tc_prompt "Seleccione usuario a eliminar"
    read -r sel

    [[ "$sel" == "0" || -z "$sel" ]] && return

    if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#users_arr[@]} )); then
        tc_msg_err "Opción no válida."
        tc_pause
        return
    fi

    local sel_idx=$((sel - 1))
    local sel_user="${users_arr[$sel_idx]}"
    local target_uuid="${uuids_arr[$sel_idx]}"

    if ! tc_confirm "¿Eliminar al usuario '$sel_user'?"; then
        return
    fi

    local tmp="${TC_V2_CONF}.tmp"
    jq --arg id "$target_uuid" '
      .inbounds |= map(
        if ((.settings.clients? | type) == "array") then
          .settings.clients |= map(select(.id != $id))
        else
          .
        end
      )
    ' "$TC_V2_CONF" > "$tmp" && mv "$tmp" "$TC_V2_CONF"

    sed -i "/^[[:space:]]*${sel_user}[[:space:]]*|/d" "$TC_V2_REG"
    tc_v2_restart

    tc_msg_ok "Usuario '$sel_user' eliminado de V2Ray."
    tc_pause
}

# ── Desinstalación Profunda Total de V2Ray ─────────────────────
tc_v2_uninstall_all() {
    tc_clear
    tc_title "DESINSTALAR V2RAY / XRAY"

    if ! tc_confirm "¿Está seguro de desinstalar y limpiar por completo V2Ray?"; then
        return
    fi

    tc_msg_ok "Deteniendo y eliminando servicios..."
    systemctl stop v2ray >/dev/null 2>&1 || true
    systemctl stop xray >/dev/null 2>&1 || true
    systemctl disable v2ray >/dev/null 2>&1 || true
    systemctl disable xray >/dev/null 2>&1 || true

    if command -v v2ray >/dev/null 2>&1; then
        v2ray uninstall >/dev/null 2>&1 || true
    fi

    pkill -9 -x v2ray >/dev/null 2>&1 || true
    pkill -9 -x xray >/dev/null 2>&1 || true

    rm -f /etc/systemd/system/xray.service /etc/systemd/system/v2ray.service /lib/systemd/system/v2ray.service /lib/systemd/system/xray.service /etc/systemd/system/multi-v2ray.service
    systemctl daemon-reload >/dev/null 2>&1 || true

    rm -f /usr/local/bin/xray /usr/local/bin/v2ray /usr/bin/v2ray /usr/bin/xray /bin/v2ray /bin/xray
    rm -rf /etc/v2ray /usr/local/etc/v2ray /etc/xray /usr/local/etc/xray /etc/tunnelcore/v2ray /var/log/v2ray /var/log/xray /root/.v2ray /root/.xray

    tc_msg_ok "¡V2Ray ha sido desinstalado por completo!"
    tc_pause
}

# ── Alternar Estado del Servicio ──────────────────────────────
tc_v2_toggle_service() {
    if tc_v2_is_running; then
        systemctl stop xray >/dev/null 2>&1 || systemctl stop v2ray >/dev/null 2>&1 || true
        tc_msg_ok "Servicio V2Ray detenido [OFF]."
    else
        tc_v2_free_conflicts
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl enable xray >/dev/null 2>&1 || true
        systemctl restart xray >/dev/null 2>&1 || systemctl restart v2ray >/dev/null 2>&1 || true
        sleep 0.5
        if tc_v2_is_running; then
            tc_msg_ok "Servicio V2Ray iniciado [ON] correctamente."
        else
            tc_msg_warn "El servicio intentó iniciar pero no está activo."
            printf '\n%bÚltimos logs de error:%b\n' "$TC_YELLOW" "$TC_NC"
            journalctl -u xray -n 10 --no-pager 2>/dev/null || journalctl -u v2ray -n 10 --no-pager 2>/dev/null
        fi
    fi
    tc_pause
}

# ── Configurar Dominio y Certificado TLS ──────────────────────
tc_v2_config_tls() {
    tc_clear
    tc_title "CONFIGURAR DOMINIO Y TLS"
    tc_v2_load_env

    printf '%bDominio actual:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${V2_DOMAIN:-No configurado}" "$TC_NC"
    printf '%bSNI / Bug actual:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${V2_SNI:-No configurado}" "$TC_NC"
    tc_line

    printf '%bNuevo Dominio CDN / Host:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r nd
    [[ -n "$nd" ]] && V2_DOMAIN="$nd"

    printf '%bNuevo SNI / Bug Host [Enter para usar %s]:%b ' "$TC_DARK_GREEN" "${V2_DOMAIN:-$nd}" "$TC_NC"
    read -r ns
    [[ -n "$ns" ]] && V2_SNI="$ns" || V2_SNI="$V2_DOMAIN"

    tc_v2_save_env
    tc_v2_restart
    tc_msg_ok "Configuración TLS actualizada."
    tc_pause
}

# ── Menú Principal V2Ray ───────────────────────────────────────
tc_xray_menu() {
    while true; do
        tc_clear
        tc_v2_load_env
        tc_title "GESTIÓN DE V2RAY / XRAY $(tc_v2_status_mark)"

        if ! tc_v2_is_installed; then
            tc_opt "1" "CONFIGURAR V2RAY DESDE CERO (ASISTENTE COMPLETO)"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_v2_setup_wizard ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        else
            printf '%bPUERTOS:%b %bHTTP %s | TLS %s%b  %bPATH:%b %b%s%b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "${V2_HTTP_PORT:-80}" "${V2_TLS_PORT:-443}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "${V2_PATH:-/tunnelcore}" "$TC_NC"
            printf '%bDOMINIO CDN:%b %b%s%b  %bESTADO:%b %b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "${V2_DOMAIN:-No configurado}" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$(tc_v2_status_mark)"
            tc_line
            tc_opt "1" "AGREGAR USUARIO V2RAY"
            tc_opt "2" "LISTAR USUARIOS REGISTRADOS"
            tc_opt "3" "RENOVAR DÍAS DE USUARIO"
            tc_opt "4" "MODIFICAR UUID DE USUARIO"
            tc_opt "5" "ELIMINAR USUARIO"
            tc_line
            tc_opt "6" "INICIAR / PARAR SERVICIO" "  $(tc_v2_status_mark)"
            tc_opt "7" "CONFIGURAR DOMINIO CDN / HOST TLS"
            tc_opt "8" "REINICIAR SERVICIO V2RAY"
            tc_opt "9" "VER LOGS EN TIEMPO REAL"
            tc_opt "10" "RECONFIGURAR V2RAY DESDE CERO"
            tc_opt "11" "DESINSTALAR V2RAY"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt

            case "$opt" in
                1|01) tc_v2_add_user_simple ;;
                2|02) tc_v2_list_users ;;
                3|03) tc_v2_renew_user ;;
                4|04) tc_v2_modify_uuid ;;
                5|05) tc_v2_del_user ;;
                6|06) tc_v2_toggle_service ;;
                7|07) tc_v2_config_tls ;;
                8|08)
                    tc_v2_restart
                    tc_msg_ok "Servicio V2Ray reiniciado."
                    tc_pause
                    ;;
                9|09)
                    tc_clear
                    tc_title "LOGS V2RAY EN VIVO (Ctrl+C para salir)"
                    journalctl -u xray -f --no-pager 2>/dev/null || journalctl -u v2ray -f --no-pager 2>/dev/null
                    ;;
                10) tc_v2_setup_wizard ;;
                11) tc_v2_uninstall_all ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        fi
    done
}
