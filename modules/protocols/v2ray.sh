#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/v2ray.sh
#  Gestión Avanzada de V2Ray / Xray (1:1 con Rufus / NoxuraSSH)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

SSHPLUS_NUM="$TC_GREEN"
SSHPLUS_CYAN="$TC_CYAN"
SSHPLUS_DARK_GREEN="$TC_DARK_GREEN"
SCOLOR="$TC_NC"

v2ray_resize() {
    tc_resize
}

v2ray_line() {
    tc_line
}

v2ray_title() {
    tc_title "$1"
}

v2ray_opt() {
    tc_opt "$1" "$2" "${3:-}"
}

v2ray_prompt() {
    tc_prompt "$1"
}

pausa_v2ray() {
    tc_pause
}

linea_v2ray() {
    tc_line
}

v2ray_config_file() {
    local cfg
    for cfg in /usr/local/etc/xray/config.json /etc/v2ray/config.json /etc/tunnelcore/v2ray/config.json /usr/local/etc/v2ray/config.json /etc/xray/config.json; do
        [[ -f "$cfg" ]] && echo "$cfg" && return 0
    done
    return 1
}

v2ray_ensure_legacy_config() {
    local cfg="$1"
    [[ -z "$cfg" ]] && return 0
    mkdir -p /etc/v2ray /etc/tunnelcore/v2ray /usr/local/etc/xray

    # Inyectar routing si falta en config.json para compatibilidad con v2ray_util
    if v2ray_require_jq; then
        for f in "$cfg" /etc/v2ray/config.json /usr/local/etc/xray/config.json /etc/tunnelcore/v2ray/config.json; do
            if [[ -f "$f" ]]; then
                if ! jq -e '.routing.rules' "$f" >/dev/null 2>&1; then
                    local tmp="${f}.tmp"
                    jq '. + {"routing": {"domainStrategy": "IPIfNonMatch", "rules": [{"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"}]}}' "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f" 2>/dev/null || true
                fi
            fi
        done
    fi

    [[ "$cfg" == "/etc/v2ray/config.json" ]] && return 0
    ln -sf "$cfg" /etc/v2ray/config.json 2>/dev/null || cp -f "$cfg" /etc/v2ray/config.json 2>/dev/null || true
}

v2ray_service_running() {
    systemctl is-active xray >/dev/null 2>&1 && return 0
    systemctl is-active v2ray >/dev/null 2>&1 && return 0
    pgrep -x xray >/dev/null 2>&1 && return 0
    pgrep -x v2ray >/dev/null 2>&1 && return 0
    ss -tunlp 2>/dev/null | grep -E 'v2ray|xray' >/dev/null 2>&1 && return 0
    netstat -tunlp 2>/dev/null | grep -E 'v2ray|xray' >/dev/null 2>&1 && return 0
    return 1
}

v2ray_require_jq() {
    command -v jq >/dev/null 2>&1 && return 0
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y jq >/dev/null 2>&1 || true
    fi
    command -v jq >/dev/null 2>&1
}

v2ray_restart_service() {
    systemctl stop apache2 >/dev/null 2>&1 || true
    systemctl stop nginx >/dev/null 2>&1 || true
    if systemctl is-active xray >/dev/null 2>&1; then
        systemctl restart xray >/dev/null 2>&1
    elif systemctl is-active v2ray >/dev/null 2>&1; then
        systemctl restart v2ray >/dev/null 2>&1
    elif command -v v2ray >/dev/null 2>&1; then
        v2ray restart >/dev/null 2>&1
    elif systemctl list-unit-files xray.service >/dev/null 2>&1; then
        systemctl restart xray >/dev/null 2>&1
    elif systemctl list-unit-files v2ray.service >/dev/null 2>&1; then
        systemctl restart v2ray >/dev/null 2>&1
    fi
}

v2ray_valid_uuid() {
    [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

v2ray_valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -ge 1 ]] && [[ "$1" -le 65535 ]]
}

v2ray_show_info() {
    local cfg="$(v2ray_config_file)"
    [[ -n "$cfg" ]] && v2ray_ensure_legacy_config "$cfg"

    local show_clean=0
    if command -v v2ray >/dev/null 2>&1; then
        if ! v2ray info 2>&1 | grep -qv "Traceback"; then
            show_clean=1
        fi
    else
        show_clean=1
    fi

    if [[ "$show_clean" -eq 1 ]]; then
        [[ -z "$cfg" ]] && echo -e "\033[1;31mNo se encontró config.json de V2Ray/Xray.\033[0m" && return 1
        if v2ray_require_jq; then
            jq -r '.inbounds[]? | "PUERTO: \(.port) | PROTOCOLO: \(.protocol // "desconocido") | RED: \(.streamSettings.network // "tcp")"' "$cfg" 2>/dev/null || true
        else
            grep -E '"port"|"protocol"|"network"' "$cfg" 2>/dev/null || true
        fi
    fi
}

msg01='\033[1;37m\033[1;33mUsuario vacío\033[1;31m'
msg02='\033[1;37m\033[1;33mNombre muy corto (MIN: 2 caracteres)\033[1;31m'
msg03='\033[1;37m\033[1;33mNombre muy largo (MAX: 20 caracteres)\033[1;31m'
msg08='\033[1;37m\033[1;33mDuración no válida, use solo números\033[1;31m'
msg09='\033[1;37m\033[1;33mDuración máxima un año\033[1;31m'
msg15='\033[1;37m\033[1;33m(Solo números) GB = Min: 1gb Max: 1000gb\033[1;31m'
msg16='\033[1;37m\033[1;33m(Solo números)\033[1;31m'
msg17='\033[1;37m\033[1;33m(Sin datos - Para cancelar pulse CTRL + C)\033[1;31m'

# ── Instalador Directo de Respaldo de Núcleo ──────────────────
instalar_nucleo_directo() {
    local arch asset xray_url
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) asset="Xray-linux-64.zip" ;;
        aarch64|arm64) asset="Xray-linux-arm64-v8a.zip" ;;
        arm*) asset="Xray-linux-arm32-v7a.zip" ;;
        *) asset="Xray-linux-64.zip" ;;
    esac

    xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/${asset}"
    local tmp_dir="/tmp/xray-core-inst-$$"
    mkdir -p "$tmp_dir" /usr/local/etc/xray /etc/v2ray /etc/SSHPlus/v2ray /etc/SSHPlus

    if ! curl -fsSL --connect-timeout 5 -o "${tmp_dir}/xray.zip" "$xray_url"; then
        wget -q --timeout=30 -O "${tmp_dir}/xray.zip" "$xray_url" || true
    fi

    if [[ -f "${tmp_dir}/xray.zip" ]]; then
        unzip -q -o "${tmp_dir}/xray.zip" -d "$tmp_dir" >/dev/null 2>&1 || true
        if [[ -f "${tmp_dir}/xray" ]]; then
            install -m 755 "${tmp_dir}/xray" /usr/local/bin/xray
        fi
    fi
    rm -rf "$tmp_dir"

    local init_uuid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || tc_gen_uuid)"
    local init_user="admin"
    local init_exp="$(date '+%Y-%m-%d' -d '+365 days' 2>/dev/null || echo '2030-01-01')"

    # Certificados SSL para TLS 443
    mkdir -p /etc/tunnelcore/v2ray
    if [[ ! -f /etc/tunnelcore/v2ray/server.crt || ! -f /etc/tunnelcore/v2ray/server.key ]]; then
        openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
            -keyout /etc/tunnelcore/v2ray/server.key -out /etc/tunnelcore/v2ray/server.crt -subj "/CN=tunnelcore-v2ray" >/dev/null 2>&1 || true
        chmod 600 /etc/tunnelcore/v2ray/server.key /etc/tunnelcore/v2ray/server.crt 2>/dev/null || true
    fi

    cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vmess-ws-http",
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
          "path": "/tunnelcore"
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
          "path": "/tunnelcore"
        }
      }
    },
    {
      "tag": "vmess-ws-tls",
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
              "certificateFile": "/etc/tunnelcore/v2ray/server.crt",
              "keyFile": "/etc/tunnelcore/v2ray/server.key"
            }
          ]
        },
        "wsSettings": {
          "path": "/tunnelcore"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

    ln -sf /usr/local/etc/xray/config.json /etc/v2ray/config.json 2>/dev/null || cp -f /usr/local/etc/xray/config.json /etc/v2ray/config.json 2>/dev/null || true

    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=TunnelCore V2Ray/Xray Service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray >/dev/null 2>&1

    [[ -f /etc/SSHPlus/RegV2ray ]] || touch /etc/SSHPlus/RegV2ray
    if ! grep -q "$init_uuid" /etc/SSHPlus/RegV2ray 2>/dev/null; then
        echo "  $init_uuid | $init_user | $init_exp " >> /etc/SSHPlus/RegV2ray
    fi
}

# ── Instalador V2Ray ──────────────────────────────────────────
intallv2ray() {
    tc_clear
    v2ray_title "INSTALADOR V2RAY"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y curl wget unzip ca-certificates jq uuid-runtime openssl python3 python3-pip python3-setuptools >/dev/null 2>&1 || true
    fi

    # Corregir pip si es Python 3.8
    local py_ver
    py_ver="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "3.8")"
    if [[ "$py_ver" == "3.8" ]] && ! command -v pip >/dev/null 2>&1 && ! command -v pip3 >/dev/null 2>&1; then
        curl -fsSL https://bootstrap.pypa.io/pip/3.8/get-pip.py | python3 >/dev/null 2>&1 || true
    fi

    echo -e "\033[1;32m[✓] Descargando e iniciando instalador Multi-V2Ray...\033[0m"
    local installed=0
    if bash <(curl -sL https://multi.netlify.app/v2ray.sh) -k 2>/dev/null; then
        installed=1
    elif bash <(curl -sL https://raw.githubusercontent.com/Jrohy/multi-v2ray/master/v2ray.sh) 2>/dev/null; then
        installed=1
    fi

    # Si no dejó comando v2ray o falló config.json, configurar núcleo directamente
    if ! command -v v2ray >/dev/null 2>&1 || [[ -z "$(v2ray_config_file)" ]]; then
        echo -e "\033[1;33mConfigurando núcleo V2Ray oficial de alta velocidad...\033[0m"
        instalar_nucleo_directo
    else
        v2ray_title "ELIJA EL PROTOCOLO V2RAY"
        v2ray stream
        tc_clear
        linea_v2ray
        v2ray_title "INDIQUE EL PUERTO V2RAY [8443] o [443]"
        v2ray port
        tc_clear
    fi

    mkdir -p /etc/SSHPlus /etc/tunnelcore/v2ray
    local USRdatabase="/etc/SSHPlus/RegV2ray"
    [[ ! -e ${USRdatabase} ]] && touch ${USRdatabase}
    sort ${USRdatabase} | uniq > "${USRdatabase}tmp"
    mv -f "${USRdatabase}tmp" "${USRdatabase}"

    local config_v2ray="$(v2ray_config_file)"
    if [[ -n "$config_v2ray" ]]; then
        v2ray_ensure_legacy_config "$config_v2ray"
        v2ray_restart_service
    fi

    linea_v2ray
    v2ray_title "INFORMACIÓN DE CUENTA"
    v2ray_show_info
    linea_v2ray
    pausa_v2ray
}

# ── Desinstalador Oficial ─────────────────────────────────────
unistallv2() {
    tc_clear
    v2ray_title "DESINSTALAR V2RAY"
    if command -v v2ray >/dev/null 2>&1; then
        v2ray uninstall >/dev/null 2>&1 || true
    fi
    systemctl stop xray >/dev/null 2>&1 || true
    systemctl stop v2ray >/dev/null 2>&1 || true
    systemctl disable xray >/dev/null 2>&1 || true
    systemctl disable v2ray >/dev/null 2>&1 || true
    pkill -9 -x v2ray >/dev/null 2>&1 || true
    pkill -9 -x xray >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/xray.service /etc/systemd/system/v2ray.service /lib/systemd/system/v2ray.service /lib/systemd/system/xray.service
    rm -f /usr/local/bin/xray /usr/local/bin/v2ray /usr/bin/v2ray /usr/bin/xray /bin/v2ray /bin/xray
    rm -rf /usr/local/etc/xray /etc/xray /var/log/xray /etc/v2ray /usr/local/etc/v2ray /var/log/v2ray /etc/SSHPlus/RegV2ray /etc/tunnelcore/v2ray
    systemctl daemon-reload >/dev/null 2>&1
    echo -e "\n\033[1;32mV2RAY ELIMINADO CORRECTAMENTE.\033[0m"
    linea_v2ray
    pausa_v2ray
}

# ── WebSocket Configuration ───────────────────────────────────
v2ray_set_websocket() {
    local cfg path host tmp
    tc_clear
    v2ray_title "ACTIVAR WEBSOCKET V2RAY"
    cfg="$(v2ray_config_file)"
    [[ -z "$cfg" ]] && echo -e "\033[1;31mNo se encontró config.json de V2Ray/Xray.\033[0m" && pausa_v2ray && return
    v2ray_ensure_legacy_config "$cfg"
    cfg="/etc/v2ray/config.json"
    printf '%bPATH WEBSOCKET [Enter = /tunnelcore]:%b ' "$SSHPLUS_DARK_GREEN" "$SCOLOR"
    read -r path
    [[ -z "$path" ]] && path="/tunnelcore"
    [[ "$path" != /* ]] && path="/$path"
    printf '%bHOST / DOMINIO [opcional]:%b ' "$SSHPLUS_DARK_GREEN" "$SCOLOR"
    read -r host
    cp "$cfg" "$cfg.bak-$(date +%s)"
    if v2ray_require_jq; then
        tmp="${cfg}.tmp"
        if [[ -n "$host" ]]; then
            jq --arg path "$path" --arg host "$host" '
              .inbounds |= map(
                .streamSettings = ((.streamSettings // {}) + {
                  "network": "ws",
                  "security": (.streamSettings.security // "none"),
                  "wsSettings": {
                    "path": $path,
                    "headers": {
                      "Host": $host
                    }
                  }
                })
              )
            ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
        else
            jq --arg path "$path" '
              .inbounds |= map(
                .streamSettings = ((.streamSettings // {}) + {
                  "network": "ws",
                  "security": (.streamSettings.security // "none"),
                  "wsSettings": {
                    "path": $path
                  }
                })
              )
            ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
        fi
    fi
    v2ray_restart_service
    linea_v2ray
    echo -e "\033[1;32mWebSocket aplicado correctamente.\033[0m"
    echo -e "${SSHPLUS_DARK_GREEN}PATH:${SCOLOR} \033[1;37m$path\033[0m"
    [[ -n "$host" ]] && echo -e "${SSHPLUS_DARK_GREEN}HOST:${SCOLOR} \033[1;37m$host\033[0m"
    linea_v2ray
    pausa_v2ray
}

protocolv2ray() {
    local opt
    tc_clear
    v2ray_title "CAMBIAR PROTOCOLO V2RAY"
    v2ray_opt "1" "Abrir selector original"
    v2ray_opt "3" "WebSocket"
    v2ray_line
    v2ray_opt "0" "VOLVER"
    v2ray_line
    printf '%bOpción:%b ' "$SSHPLUS_CYAN" "$SCOLOR" && read -r opt
    case "$opt" in
        3|03) v2ray_set_websocket ;;
        1|01)
            if ! command -v v2ray >/dev/null 2>&1; then
                echo -e "\033[1;31mEl selector original requiere el comando v2ray.\033[0m"
                pausa_v2ray
                return
            fi
            v2ray stream
            pausa_v2ray
            ;;
        0|00) return ;;
        *) echo -e "\033[1;31mOpción no válida!\033[0m"; sleep 1; protocolv2ray ;;
    esac
}

tls() {
    tc_clear
    v2ray_title "Activar o desactivar TLS"
    if ! command -v v2ray >/dev/null 2>&1; then
        echo -e "\033[1;31mLa opción TLS original requiere el comando v2ray.\033[0m"
        pausa_v2ray
        return
    fi
    v2ray tls
    linea_v2ray
    pausa_v2ray
}

portv() {
    tc_clear
    v2ray_title "CAMBIAR PUERTO V2RAY"
    if ! command -v v2ray >/dev/null 2>&1; then
        echo -e "\033[1;31mLa opción cambiar puerto original requiere el comando v2ray.\033[0m"
        pausa_v2ray
        return
    fi
    v2ray port
    linea_v2ray
    pausa_v2ray
}

agregar_puerto_v2ray() {
    local cfg tmp port base_port
    tc_clear
    v2ray_title "AGREGAR PUERTO V2RAY"
    cfg="$(v2ray_config_file)"
    [[ -z "$cfg" ]] && echo -e "\033[1;31mNo se encontró config.json de V2Ray/Xray.\033[0m" && pausa_v2ray && return
    v2ray_ensure_legacy_config "$cfg"
    cfg="/etc/v2ray/config.json"
    if ! v2ray_require_jq; then
        echo -e "\033[1;31mjq no está instalado.\033[0m"
        pausa_v2ray
        return
    fi
    base_port="$(jq -r '.inbounds[]? | select((.settings.clients? | type) == "array") | .port' "$cfg" | sed '/^$/d' | head -1)"
    [[ -z "$base_port" ]] && echo -e "\033[1;31mNo hay inbound base para duplicar.\033[0m" && pausa_v2ray && return
    echo -e "\033[1;33mPuerto base detectado: \033[1;37m$base_port\033[0m"
    while true; do
        printf '%bNUEVO PUERTO V2RAY:%b ' "$SSHPLUS_DARK_GREEN" "$SCOLOR" && read -r port
        [[ -z "$port" ]] && echo -e "$msg17" && continue
        if ! v2ray_valid_port "$port"; then
            echo -e "\033[1;31mPuerto no válido. Use 1-65535.\033[0m"
            continue
        fi
        if jq -e --argjson port "$port" '.inbounds[]? | select(.port == $port)' "$cfg" >/dev/null; then
            echo -e "\033[1;31mYa existe un inbound con ese puerto.\033[0m"
            continue
        fi
        break
    done
    cp "$cfg" "$cfg.bak-$(date +%s)"
    tmp="${cfg}.tmp"
    jq --argjson base "$base_port" --argjson port "$port" '
      .inbounds += [
        (.inbounds[] | select(.port == $base and ((.settings.clients? | type) == "array")) | .port = $port | .settings.clients = [])
      ]
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    v2ray_restart_service
    echo -e "\033[1;32mPuerto agregado correctamente.\033[0m"
    echo -e "\033[1;33mNuevo puerto: \033[1;37m$port\033[0m"
    pausa_v2ray
}

stats() {
    tc_clear
    v2ray_title "ESTADÍSTICAS DE CONSUMO"
    if command -v v2ray >/dev/null 2>&1; then
        v2ray stats
    else
        echo -e "\033[1;33mComando v2ray stats no disponible.\033[0m"
    fi
    linea_v2ray
    pausa_v2ray
}

infocuenta() {
    tc_clear
    v2ray_title "INFORMACIÓN DE CUENTA"
    v2ray_show_info
    linea_v2ray
    pausa_v2ray
}

# ── Crear Usuario V2Ray ───────────────────────────────────────
addusr() {
    tc_clear
    v2ray_title "AÑADIR USUARIO | UUID V2RAY"
    local cfg tmp
    cfg="$(v2ray_config_file)"
    [[ -z "$cfg" ]] && echo -e "\033[1;31mNo se encontró config.json de V2Ray/Xray.\033[0m" && pausa_v2ray && return
    v2ray_ensure_legacy_config "$cfg"
    cfg="/etc/v2ray/config.json"
    if ! v2ray_require_jq; then
        echo -e "\033[1;31mjq no está instalado.\033[0m"
        pausa_v2ray
        return
    fi

    # 1. Nombre
    local nick
    while true; do
        printf '%bNOMBRE DE USUARIO:%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r nick
        nick="$(echo "$nick" | sed -e 's/[^a-z0-9 -]//ig')"
        if [[ -z "$nick" ]]; then
            echo -e "$msg17" && continue
        elif [[ "${#nick}" -lt 2 ]]; then
            echo -e "$msg02" && continue
        elif [[ "${#nick}" -gt 20 ]]; then
            echo -e "$msg03" && continue
        fi
        break
    done

    # 2. Protocolo
    local proto_choice="1" proto_name="VMess" proto_tag="vmess"
    while true; do
        echo ""
        echo -e "\033[1;37mSELECCIONAR PROTOCOLO:\033[0m"
        v2ray_opt "1" "VMess"
        v2ray_opt "2" "VLESS"
        printf '%bOpción:%b ' "$SSHPLUS_CYAN" "$SCOLOR" && read -r proto_choice
        case "$proto_choice" in
            1) proto_name="VMess"; proto_tag="vmess"; break ;;
            2) proto_name="VLESS"; proto_tag="vless"; break ;;
            *) echo -e "\033[1;31mOpción no válida!\033[0m" ;;
        esac
    done

    # 3. Puerto
    mapfile -t v2_ports < <(jq -r '.inbounds[]? | select((.settings.clients? | type) == "array") | .port' "$cfg" 2>/dev/null | sed '/^$/d' | sort -n | uniq)
    local selected_port="" selected_ports_disp="" apply_all=false
    if [[ "${#v2_ports[@]}" -eq 0 ]]; then
        printf '%bPUERTO V2RAY (ej: 80, 443, 8080):%b ' "$TC_DARK_GREEN" "$TC_NC" && read -r selected_port
        [[ -z "$selected_port" ]] && selected_port="80"
        selected_ports_disp="$selected_port"
    elif [[ "${#v2_ports[@]}" -eq 1 ]]; then
        selected_port="${v2_ports[0]}"
        selected_ports_disp="$selected_port"
        echo -e "\033[1;33mPuerto V2Ray detectado: \033[1;37m${selected_port}\033[0m"
    else
        echo ""
        echo -e "\033[1;37mSELECCIONAR PUERTO V2RAY:\033[0m"
        for i in "${!v2_ports[@]}"; do
            v2ray_opt "$((i+1))" "Puerto ${v2_ports[$i]}"
        done
        v2ray_opt "$(( ${#v2_ports[@]} + 1 ))" "TODOS LOS PUERTOS ($(IFS=,; echo "${v2_ports[*]}"))"
        while true; do
            printf '%bOpción:%b ' "$SSHPLUS_CYAN" "$SCOLOR" && read -r p_opt
            if [[ "$p_opt" -ge 1 && "$p_opt" -le "${#v2_ports[@]}" ]] 2>/dev/null; then
                selected_port="${v2_ports[$((p_opt-1))]}"
                selected_ports_disp="$selected_port"
                apply_all=false
                break
            elif [[ "$p_opt" -eq "$(( ${#v2_ports[@]} + 1 ))" ]] 2>/dev/null; then
                apply_all=true
                selected_port="${v2_ports[0]}"
                selected_ports_disp="$(IFS=,; echo "${v2_ports[*]}")"
                break
            else
                echo -e "\033[1;31mOpción no válida!\033[0m"
            fi
        done
    fi

    # 4. UUID
    local UUID
    while true; do
        echo ""
        echo -e "\033[1;37mCONFIGURAR UUID / ID:\033[0m"
        v2ray_opt "1" "Generar automáticamente (Aleatorio)"
        v2ray_opt "2" "Ingresar manualmente"
        printf '%bOpción:%b ' "$SSHPLUS_CYAN" "$SCOLOR" && read -r uuidopc
        case "$uuidopc" in
            1)
                UUID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || tc_gen_uuid)"
                break
                ;;
            2)
                printf '%bUUID:%b ' "$TC_DARK_GREEN" "$TC_NC" && read -r UUID
                [[ -z "$UUID" ]] && echo -e "$msg17" && continue
                if ! v2ray_valid_uuid "$UUID"; then
                    echo -e "\033[1;31mUUID no válido.\033[0m"
                    continue
                fi
                break
                ;;
            *) echo -e "\033[1;31mOpción no válida!\033[0m" ;;
        esac
    done

    # 5. Modo de Conexión
    local tls_opt="1" tls_mode="none" add_host="" host_header="" sni_host="" ext_port="$selected_port"
    local cur_domain="$(cat /etc/SSHPlus/v2ray/domain 2>/dev/null || cat /etc/xray/domain 2>/dev/null || cat /etc/v2ray/domain 2>/dev/null || echo "")"
    local vps_ip="$(tc_public_ip)"

    while true; do
        echo ""
        echo -e "\033[1;37mMODO DE CONEXIÓN / SEGURIDAD TLS:\033[0m"
        v2ray_opt "1" "DIRECTO A IP (Sin TLS / HTTP WS - Puerto $selected_port)"
        v2ray_opt "2" "CLOUDFLARE CDN (Con TLS / Dominio - Puerto 443 + SNI Bug)"
        printf '%bOpción:%b ' "$SSHPLUS_CYAN" "$SCOLOR" && read -r tls_opt
        case "$tls_opt" in
            1)
                tls_mode="none"
                add_host="$vps_ip"
                ext_port="$selected_port"
                host_header=""
                sni_host=""
                break
                ;;
            2)
                tls_mode="tls"
                ext_port="443"
                echo ""
                if [[ -n "$cur_domain" ]]; then
                    printf '%bDOMINIO / HOST ADD (actual: %s) [Enter para usar]:%b ' "$TC_DARK_GREEN" "$cur_domain" "$TC_NC"
                    read -r user_domain
                    [[ -n "$user_domain" ]] && add_host="$user_domain" || add_host="$cur_domain"
                else
                    while true; do
                        printf '%bDOMINIO / HOST ADD (ej: midominio.com):%b ' "$TC_DARK_GREEN" "$TC_NC"
                        read -r user_domain
                        if [[ -z "$user_domain" ]]; then
                            echo -e "\033[1;31mDebe ingresar un dominio.\033[0m"
                            continue
                        fi
                        add_host="$user_domain"
                        mkdir -p /etc/SSHPlus/v2ray
                        echo "$add_host" > /etc/SSHPlus/v2ray/domain
                        break
                    done
                fi

                echo ""
                printf '%bSNI / BUG HOST (ej: bug.operadora.com) [Enter para usar %s]:%b ' "$TC_DARK_GREEN" "$add_host" "$TC_NC"
                read -r user_sni
                if [[ -n "$user_sni" ]]; then
                    sni_host="$user_sni"
                    host_header="$user_sni"
                else
                    sni_host="$add_host"
                    host_header="$add_host"
                fi
                break
                ;;
            *) echo -e "\033[1;31mOpción no válida!\033[0m" ;;
        esac
    done

    # 6. Días de Duración
    local diasuser
    while true; do
        echo ""
        printf '%bDURACIÓN DEL USUARIO (DÍAS):%b ' "$TC_DARK_GREEN" "$TC_NC" && read -r diasuser
        if [[ -z "$diasuser" ]]; then
            echo -e "$msg17" && continue
        elif ! [[ "$diasuser" =~ ^[0-9]+$ ]]; then
            echo -e "$msg08" && continue
        elif [[ "$diasuser" -gt "365" ]]; then
            echo -e "$msg09" && continue
        fi
        break
    done

    local valid="$(date '+%C%y-%m-%d' -d "+${diasuser} days" 2>/dev/null || echo "2030-01-01")"
    local datexp="$(date "+%F" -d "+${diasuser} days" 2>/dev/null || echo "2030-01-01")"

    # 7. Insertar en config.json
    cp "$cfg" "$cfg.bak-$(date +%s)"
    tmp="${cfg}.tmp"

    if [[ "$apply_all" == true ]]; then
        jq --arg uuid "$UUID" --arg proto "$proto_tag" '
          .inbounds |= map(
            if ((.settings.clients? | type) == "array") then
              if (.settings.clients | any(.id == $uuid)) then
                .
              else
                .settings.clients += [(
                  if ($proto == "vless" or .protocol == "vless") then
                    {"id": $uuid}
                  else
                    {"id": $uuid, "alterId": 0}
                  end
                )]
              end
            else
              .
            end
          )
        ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    else
        local tgt_p=$selected_port
        jq --arg uuid "$UUID" --argjson tgt "$tgt_p" --arg proto "$proto_tag" '
          .inbounds |= map(
            if (.port == $tgt and ((.settings.clients? | type) == "array")) then
              if (.settings.clients | any(.id == $uuid)) then
                .
              else
                .settings.clients += [(
                  if ($proto == "vless" or .protocol == "vless") then
                    {"id": $uuid}
                  else
                    {"id": $uuid, "alterId": 0}
                  end
                )]
              end
            else
              .
            end
          )
        ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    fi

    # 8. Registro y Reinicio
    mkdir -p /etc/SSHPlus/v2ray
    if ! grep -q "$UUID.*$nick" /etc/SSHPlus/RegV2ray 2>/dev/null; then
        echo "  $UUID | $nick | $valid " >> /etc/SSHPlus/RegV2ray
    fi
    v2ray_restart_service

    # 9. Generar Enlace URI
    local path_ws="$(jq -r --argjson p "${selected_port:-80}" '.inbounds[]? | select(.port == $p) | .streamSettings.wsSettings.path // .streamSettings.xhttpSettings.path // ""' "$cfg" 2>/dev/null)"
    [[ -z "$path_ws" || "$path_ws" == "null" ]] && path_ws="$(jq -r '.inbounds[0].streamSettings.wsSettings.path // .inbounds[0].streamSettings.xhttpSettings.path // "/v2ray"' "$cfg" 2>/dev/null)"
    [[ -z "$path_ws" || "$path_ws" == "null" ]] && path_ws="/v2ray"

    local uri=""
    if [[ "$proto_tag" == "vmess" ]]; then
        local vmess_json
        vmess_json=$(cat <<EOF
{
  "v": "2",
  "ps": "$nick",
  "add": "${add_host}",
  "port": "${ext_port}",
  "id": "$UUID",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "",
  "host": "${host_header}",
  "path": "${path_ws}",
  "tls": "${tls_mode}",
  "sni": "${sni_host}",
  "alpn": "",
  "fp": ""
}
EOF
)
        local vmess_b64="$(printf '%s' "$vmess_json" | base64 | tr -d '\n\r ')"
        uri="vmess://${vmess_b64}"
    else
        local enc_path="$(printf '%s' "$path_ws" | sed 's/\//%2F/g')"
        if [[ "$tls_mode" == "tls" ]]; then
            uri="vless://${UUID}@${add_host}:${ext_port}?type=ws&security=tls&sni=${sni_host}&host=${host_header}&path=${enc_path}#${nick}"
        else
            uri="vless://${UUID}@${add_host}:${ext_port}?type=ws&security=none&path=${enc_path}#${nick}"
        fi
    fi

    # 10. Mostrar Ficha
    tc_clear
    v2ray_title "USUARIO V2RAY CREADO CON ÉXITO"
    linea_v2ray
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "USUARIO:" "$nick"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "PROTOCOLO:" "$proto_name"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "PUERTO(S) VPS:" "$selected_ports_disp"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "PUERTO CONEXIÓN:" "$ext_port"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "UUID / ID:" "$UUID"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "SEGURIDAD TLS:" "$tls_mode"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "SERVIDOR (ADD):" "$add_host"
    [[ "$tls_mode" == "tls" ]] && printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "SNI / BUG HOST:" "$sni_host"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "PATH:" "$path_ws"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s (%s días)\033[0m\n" "EXPIRA:" "$datexp" "$diasuser"
    linea_v2ray
    echo -e "\033[1;33mENLACE URI (Copiar para importar):\033[0m\n"
    echo -e "\033[1;36m${uri}\033[0m\n"
    linea_v2ray
    pausa_v2ray
}

# ── Eliminar Usuario ──────────────────────────────────────────
delusr() {
    tc_clear
    v2ray_title "ELIMINAR USUARIO V2RAY"
    local cfg tmp
    cfg="$(v2ray_config_file)"
    [[ -n "$cfg" ]] && v2ray_ensure_legacy_config "$cfg" && cfg="/etc/v2ray/config.json"
    [[ ! -s /etc/SSHPlus/RegV2ray ]] && echo -e "\033[1;31mNo hay usuarios V2RAY registrados.\033[0m" && pausa_v2ray && return
    echo -e "\033[1;37m        USUARIOS REGISTRADOS A ELIMINAR\033[0m"
    v2ray_line
    printf "\033[1;37m%-20s %s\033[0m\n" "NOMBRE" "UUID"
    mapfile -t uuid_list < <(awk -F'|' '{gsub(/ /,"",$1); if($1!="") print $1}' /etc/SSHPlus/RegV2ray)
    mapfile -t user_list < <(awk -F'|' '{gsub(/^ +| +$/,"",$2); if($1!="") print $2}' /etc/SSHPlus/RegV2ray)
    mapfile -t line_list < <(awk -F'|' '{gsub(/ /,"",$1); if($1!="") print NR}' /etc/SSHPlus/RegV2ray)
    for i in "${!uuid_list[@]}"; do
        printf "%b[%s]\033[0m \033[1;37m>\033[0m \033[1;37m%-20s\033[0m \033[1;33m%s\033[0m\n" "$SSHPLUS_NUM" "$((i+1))" "${user_list[$i]}" "${uuid_list[$i]}"
    done
    v2ray_opt "0" "CANCELAR"
    v2ray_line
    local uuid_sel
    while true; do
        printf '%bOpción:%b ' "$SSHPLUS_CYAN" "$SCOLOR"
        read -r uuid_sel
        [[ "$uuid_sel" = "0" ]] && return
        [[ "$uuid_sel" =~ ^[0-9]+$ ]] && [[ "$uuid_sel" -ge 1 ]] && [[ "$uuid_sel" -le "${#uuid_list[@]}" ]] && break
        echo -e "\033[1;31mOpción no válida!\033[0m"
        sleep 1
    done
    local uuidel="${uuid_list[$((uuid_sel-1))]}"
    local nick_del="${user_list[$((uuid_sel-1))]}"
    local linePre="${line_list[$((uuid_sel-1))]}"
    sed -i "${linePre}d" /etc/SSHPlus/RegV2ray
    if [[ -n "$cfg" ]] && grep -q "$uuidel" "$cfg"; then
        if v2ray_require_jq; then
            cp "$cfg" "$cfg.bak-$(date +%s)"
            tmp="${cfg}.tmp"
            jq --arg uuid "$uuidel" '
              .inbounds |= map(
                if ((.settings.clients? | type) == "array") then
                  .settings.clients |= map(select(.id != $uuid))
                else
                  .
                end
              )
            ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
            v2ray_restart_service
        fi
    fi
    echo ""
    linea_v2ray
    echo -e "\e[92m     USUARIO ${nick_del} ELIMINADO DE TODOS LOS PUERTOS "
    linea_v2ray
    pausa_v2ray
}

# ── Mostrar Usuarios ──────────────────────────────────────────
mosusr_kk() {
    tc_clear
    v2ray_title "USUARIOS V2RAY REGISTRADOS"
    local VPSsec=$(date +%s)
    if [[ ! -s /etc/SSHPlus/RegV2ray ]]; then
        echo -e "----- NINGÚN USUARIO REGISTRADO -----"
        v2ray_line
        pausa_v2ray
        return
    fi
    printf "\033[1;37m%-36s %-14s %s\033[0m\n" "UUID" "USUARIO" "EXPIRA"
    printf "\033[1;37m------------------------------------------------------------\033[0m\n"
    while IFS='|' read -r uuid user expire; do
        uuid="$(echo "$uuid" | xargs)"
        user="$(echo "$user" | xargs)"
        expire="$(echo "$expire" | xargs)"
        [[ -z "$uuid" ]] && continue
        if [[ -n "$expire" ]]; then
            DataSec=$(date +%s --date="$expire" 2>/dev/null || echo "")
            if [[ -n "$DataSec" ]]; then
                [[ "$VPSsec" -gt "$DataSec" ]] && EXPTIME="\033[1;31mEXPIRADO\033[0m" || EXPTIME="\033[1;32m$(($(($DataSec - $VPSsec)) / 86400)) Días\033[0m"
            else
                EXPTIME="\033[1;31mS/R\033[0m"
            fi
        else
            EXPTIME="\033[1;31mS/R\033[0m"
        fi
        printf "\033[1;33m%s\033[0m %b>\033[0m \033[1;37m%s\033[0m %b>\033[0m %b\n" "$uuid" "$SSHPLUS_CYAN" "$user" "$SSHPLUS_CYAN" "$EXPTIME"
    done < /etc/SSHPlus/RegV2ray
    v2ray_line
    pausa_v2ray
}

# ── Modificar JSON / UUID / Path ──────────────────────────────
editar_json_v2ray() {
    tc_clear
    linea_v2ray
    v2ray_title "MODIFICAR JSON V2RAY"
    linea_v2ray
    local cfg="$(v2ray_config_file)"
    [[ -z "$cfg" ]] && echo -e "\033[1;31mNo existe config.json de V2Ray/Xray\033[0m" && pausa_v2ray && return
    v2ray_ensure_legacy_config "$cfg"
    cfg="/etc/v2ray/config.json"
    cp "$cfg" "$cfg.bak-$(date +%s)"
    if command -v nano >/dev/null 2>&1; then
        nano "$cfg"
    else
        vi "$cfg"
    fi
    v2ray_restart_service
    echo -e "\033[1;32mJSON actualizado y servicio V2RAY reiniciado.\033[0m"
    pausa_v2ray
}

modificar_uuid_v2ray() {
    tc_clear
    v2ray_title "MODIFICAR UUID V2RAY"
    local cfg tmp
    cfg="$(v2ray_config_file)"
    [[ -z "$cfg" ]] && echo -e "\033[1;31mNo existe config.json de V2Ray/Xray\033[0m" && pausa_v2ray && return
    v2ray_ensure_legacy_config "$cfg"
    cfg="/etc/v2ray/config.json"
    if ! v2ray_require_jq; then
        echo -e "\033[1;31mjq no está instalado.\033[0m"
        pausa_v2ray
        return
    fi
    [[ ! -s /etc/SSHPlus/RegV2ray ]] && echo -e "\033[1;31mNo hay usuarios V2RAY registrados.\033[0m" && pausa_v2ray && return
    echo -e "\033[1;37m        SELECCIONAR USUARIO (UUID) PARA MODIFICAR\033[0m"
    v2ray_line
    mapfile -t uuid_list < <(awk -F'|' '{gsub(/ /,"",$1); if($1!="") print $1}' /etc/SSHPlus/RegV2ray)
    for i in "${!uuid_list[@]}"; do
        v2ray_opt "$((i+1))" "${uuid_list[$i]}"
    done
    v2ray_opt "0" "CANCELAR"
    v2ray_line
    local uuid_sel
    while true; do
        printf '%bOpción:%b ' "$SSHPLUS_CYAN" "$SCOLOR"
        read -r uuid_sel
        [[ "$uuid_sel" = "0" ]] && return
        [[ "$uuid_sel" =~ ^[0-9]+$ ]] && [[ "$uuid_sel" -ge 1 ]] && [[ "$uuid_sel" -le "${#uuid_list[@]}" ]] && break
        echo -e "\033[1;31mOpción no válida!\033[0m"
        sleep 1
    done
    local uuid_actual="${uuid_list[$((uuid_sel-1))]}"
    printf '%bNuevo UUID (Enter para generar):%b ' "$TC_DARK_GREEN" "$TC_NC" && read -r uuid_nuevo
    [[ -z "$uuid_nuevo" ]] && uuid_nuevo="$(uuidgen 2>/dev/null || tc_gen_uuid)"
    if ! v2ray_valid_uuid "$uuid_nuevo"; then
        echo -e "\033[1;31mUUID no válido.\033[0m"
        pausa_v2ray
        return
    fi
    cp "$cfg" "$cfg.bak-$(date +%s)"
    tmp="${cfg}.tmp"
    jq --arg old "$uuid_actual" --arg new "$uuid_nuevo" '
      .inbounds |= map(
        if ((.settings.clients? | type) == "array") then
          .settings.clients |= map(if .id == $old then .id = $new else . end)
        else
          .
        end
      )
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    sed -i "s/$uuid_actual/$uuid_nuevo/g" /etc/SSHPlus/RegV2ray
    v2ray_restart_service
    echo -e "\033[1;32mUUID modificado correctamente.\033[0m"
    echo -e "\033[1;33mNuevo UUID: \033[1;37m$uuid_nuevo\033[0m"
    pausa_v2ray
}

modificar_path_v2ray() {
    local cfg tmp cur_path new_path
    tc_clear
    v2ray_title "MODIFICAR PATH WEBSOCKET V2RAY"
    cfg="$(v2ray_config_file)"
    [[ -z "$cfg" ]] && echo -e "\033[1;31mNo se encontró config.json de V2Ray/Xray.\033[0m" && pausa_v2ray && return
    v2ray_ensure_legacy_config "$cfg"
    cfg="/etc/v2ray/config.json"
    if ! v2ray_require_jq; then
        echo -e "\033[1;31mjq no está instalado.\033[0m"
        pausa_v2ray
        return
    fi
    cur_path="$(jq -r '.inbounds[0].streamSettings.wsSettings.path // "/v2ray"' "$cfg" 2>/dev/null)"
    echo -e "${SSHPLUS_DARK_GREEN}PATH ACTUAL:${SCOLOR} \033[1;37m$cur_path\033[0m"
    printf '%bNUEVO PATH [ej: /tunnelcore]:%b ' "$SSHPLUS_DARK_GREEN" "$SCOLOR" && read -r new_path
    [[ -z "$new_path" ]] && return
    [[ "$new_path" != /* ]] && new_path="/$new_path"
    cp "$cfg" "$cfg.bak-$(date +%s)"
    tmp="${cfg}.tmp"
    jq --arg p "$new_path" '
      .inbounds |= map(
        if .streamSettings.wsSettings? then
          .streamSettings.wsSettings.path = $p
        else
          .
        end
      )
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    v2ray_restart_service
    echo -e "\033[1;32mPath modificado a $new_path y servicio reiniciado.\033[0m"
    pausa_v2ray
}

# ── Submenú Administración de Usuarios ────────────────────────
menu_usuarios_v2ray() {
    while true; do
        tc_clear
        v2ray_title "ADMINISTRAR USUARIOS V2RAY"
        v2ray_opt "1" "AÑADIR USUARIO | UUID"
        v2ray_opt "2" "ELIMINAR USUARIO V2RAY"
        v2ray_opt "3" "USUARIOS REGISTRADOS"
        v2ray_opt "4" "INFORMACIÓN DE CUENTA"
        v2ray_opt "5" "ESTADÍSTICAS DE CONSUMO"
        v2ray_line
        v2ray_opt "0" "VOLVER"
        v2ray_line
        printf '%bOpción:%b ' "$SSHPLUS_CYAN" "$SCOLOR"
        read -r usropt
        case "$usropt" in
            1|01) addusr ;;
            2|02) delusr ;;
            3|03) mosusr_kk ;;
            4|04) infocuenta ;;
            5|05) stats ;;
            0|00) break ;;
            *) echo -e "\033[1;31mOpción no válida!\033[0m"; sleep 1 ;;
        esac
    done
}

# ── Submenú Configuración de V2Ray ────────────────────────────
ajustes_v2ray() {
    while true; do
        tc_clear
        v2ray_title "CONFIGURACIÓN DE V2RAY"
        v2ray_opt "1" "CAMBIAR PROTOCOLO"
        v2ray_opt "2" "ACTIVAR TLS"
        v2ray_opt "3" "CAMBIAR PUERTO V2RAY"
        v2ray_opt "4" "MODIFICAR JSON V2RAY"
        v2ray_opt "5" "MODIFICAR UUID V2RAY"
        v2ray_opt "6" "MODIFICAR PATH V2RAY"
        v2ray_opt "7" "AGREGAR PUERTO V2RAY"
        v2ray_line
        v2ray_opt "0" "VOLVER"
        v2ray_line
        printf '%bOpción:%b ' "$SSHPLUS_CYAN" "$SCOLOR"
        read -r selection
        case "$selection" in
            1) protocolv2ray ;;
            2) tls ;;
            3) portv ;;
            4) editar_json_v2ray ;;
            5) modificar_uuid_v2ray ;;
            6) modificar_path_v2ray ;;
            7) agregar_puerto_v2ray ;;
            0) break ;;
            *) echo -e "\033[1;31mOpción no válida!\033[0m"; sleep 1 ;;
        esac
    done
}

# ── Menú Principal V2Ray (1:1 Rufus / NoxuraSSH) ───────────────
tc_xray_menu() {
    while true; do
        tc_clear
        v2ray_title "GESTIÓN DE V2RAY"
        local v2ray_running=0
        if v2ray_service_running; then
            v2ray_running=1
        fi

        if [[ "$v2ray_running" = "1" ]]; then
            printf '%bSERVICIO:%b %bV2RAY%b %b[ACTIVADO]%b\n' "$SSHPLUS_DARK_GREEN" "$SCOLOR" "$TC_YELLOW" "$SCOLOR" "$TC_GREEN" "$SCOLOR"
            v2ray_line
            v2ray_opt "1" "ADMINISTRAR USUARIOS V2RAY"
            v2ray_opt "2" "CONFIGURACIÓN DE V2RAY"
            v2ray_opt "3" "REINICIAR SERVICIO V2RAY"
            v2ray_opt "4" "REINSTALAR V2RAY"
            v2ray_opt "5" "DESINSTALAR V2RAY"
            v2ray_line
            v2ray_opt "0" "VOLVER"
        else
            printf '%bSERVICIO:%b %bV2RAY%b %b[DESACTIVADO]%b\n' "$SSHPLUS_DARK_GREEN" "$SCOLOR" "$TC_YELLOW" "$SCOLOR" "$TC_RED" "$SCOLOR"
            v2ray_line
            v2ray_opt "1" "INSTALAR V2RAY"
            v2ray_line
            v2ray_opt "0" "VOLVER"
        fi
        v2ray_line
        printf '%bOpción:%b ' "$SSHPLUS_CYAN" "$SCOLOR"
        read -r x

        if [[ "$v2ray_running" != "1" ]]; then
            case "$x" in
                1|01) intallv2ray ;;
                0|00) break ;;
                *) echo -e "\033[1;31mOpción no válida!\033[0m"; sleep 1 ;;
            esac
            continue
        fi

        case "$x" in
            1|01) menu_usuarios_v2ray ;;
            2|02) ajustes_v2ray ;;
            3|03)
                v2ray_restart_service
                echo -e "\033[1;32mServicio V2RAY reiniciado correctamente.\033[0m"
                pausa_v2ray
                ;;
            4|04) intallv2ray ;;
            5|05) unistallv2 ;;
            0|00) break ;;
            *) echo -e "\033[1;31mOpción no válida!\033[0m"; sleep 1 ;;
        esac
    done
}
