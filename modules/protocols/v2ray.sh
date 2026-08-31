#!/bin/bash
# ─────────────────────────────────────────────────────────────────
#  TunnelCore — modules/protocols/v2ray.sh
#  Gestor de V2Ray / Xray (Nativo NoxuraSSH 1:1)
#  Autor: J DAVID AG
# ─────────────────────────────────────────────────────────────────

cor1='\033[41;1;37m'
cor2='\033[44;1;37m'
scor='\033[0m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
SCOLOR="${TC_NC:-\033[0m}"
SSHPlus_NUM="${TC_GREEN:-\033[1;38;2;0;255;127m}"
SSHPlus_CYAN="${TC_CYAN:-\033[1;38;2;76;228;255m}"
SSHPlus_DARK_GREEN="${TC_DARK_GREEN:-\033[0;32m}"
v2ray_resize() {
    SSHPlus_COLS="$(tput cols 2>/dev/null || echo 80)"
    [[ ! "$SSHPlus_COLS" =~ ^[0-9]+$ ]] && SSHPlus_COLS=80
    SSHPlus_IW=60
    [[ "$SSHPlus_COLS" -lt 62 ]] && SSHPlus_IW=$(( SSHPlus_COLS - 2 ))
    [[ "$SSHPlus_IW" -lt 42 ]] && SSHPlus_IW=42
}
v2ray_line() {
    local i
    v2ray_resize
    printf '%b' "$SSHPlus_CYAN"
    for ((i=0;i<SSHPlus_IW;i++)); do printf '='; done
    printf '\033[0m\n'
}
v2ray_title() {
    local title="$1" pad
    v2ray_resize
    v2ray_line
    pad=$(( (SSHPlus_IW - ${#title}) / 2 ))
    [[ "$pad" -lt 0 ]] && pad=0
    printf '%*s%b%s\033[0m\n' "$pad" "" "$SSHPlus_CYAN" "$title"
    v2ray_line
}
v2ray_opt() {
    local n="${1#0}"
    [[ -z "$n" ]] && n="0"
    printf '%b[%s]\033[0m \033[1;37m>\033[0m \033[1;37m%s\033[0m %b\n' "$SSHPlus_NUM" "$n" "$2" "${3:-}"
}
v2ray_prompt() {
    printf '\033[1;37m>\033[0m \033[1;37m%s\033[0m \033[1;37m' "${1:-}"
}
v2ray_config_file() {
    local cfg
    for cfg in /etc/v2ray/config.json /usr/local/etc/v2ray/config.json /usr/local/etc/xray/config.json /etc/xray/config.json; do
        [[ -f "$cfg" ]] && echo "$cfg" && return 0
    done
    return 1
}
v2ray_ensure_legacy_config() {
    local cfg="$1"
    [[ -z "$cfg" || "$cfg" == "/etc/v2ray/config.json" ]] && return 0
    mkdir -p /etc/v2ray
    ln -sf "$cfg" /etc/v2ray/config.json 2>/dev/null || cp -f "$cfg" /etc/v2ray/config.json 2>/dev/null || true
}
v2ray_service_running() {
    local port
    systemctl is-active xray >/dev/null 2>&1 && return 0
    systemctl is-active v2ray >/dev/null 2>&1 && return 0
    for port in $(v2ray_ports_configured 2>/dev/null); do
    systemctl is-active "v2ray@${port}" >/dev/null 2>&1 && return 0
    systemctl is-active "xray@${port}" >/dev/null 2>&1 && return 0
    done
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
v2ray_public_ip() {
    if declare -f tc_public_ip >/dev/null 2>&1; then
    tc_public_ip
    return 0
    fi
    local ip=""
    for url in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
    ip="$(curl -4fsS --max-time 5 "$url" 2>/dev/null)" && break
    done
    [[ -z "$ip" ]] && ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    echo "${ip:-N/A}"
}
v2ray_urlencode_path() {
    local value="$1"
    value="${value//'%'/%25}"
    value="${value//' '/%20}"
    value="${value//'#'/%23}"
    value="${value//'?'/%3F}"
    value="${value//'&'/%26}"
    value="${value//'='/%3D}"
    value="${value//'/'/%2F}"
    echo "$value"
}
v2ray_port_owner() {
    local port="$1" owner=""
    if command -v ss >/dev/null 2>&1; then
    owner="$(ss -ltnup 2>/dev/null | awk -v p=":${port}" '$0 ~ p"[[:space:]]" {print; exit}')"
    elif command -v netstat >/dev/null 2>&1; then
    owner="$(netstat -ltnup 2>/dev/null | awk -v p=":${port}" '$0 ~ p"[[:space:]]" {print; exit}')"
    elif command -v lsof >/dev/null 2>&1; then
    owner="$(lsof -iTCP:"$port" -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR==2 {print; exit}')"
    fi
    echo "$owner"
}
v2ray_port_in_use_by_other() {
    local port="$1" owner cfg="$2"
    owner="$(v2ray_port_owner "$port")"
    [[ -z "$owner" ]] && return 1
    echo "$owner" | grep -Eiq 'xray|v2ray' && return 1
    if [[ -n "$cfg" && -f "$cfg" ]] && v2ray_require_jq; then
    jq -e --argjson port "$port" '.inbounds[]? | select(.port == $port)' "$cfg" >/dev/null 2>&1 && return 1
    fi
    return 0
}
v2ray_warn_port_busy() {
    local port="$1" owner
    owner="$(v2ray_port_owner "$port")"
    echo -e "\033[1;31mEl puerto $port ya esta siendo usado por otro servicio.\033[0m"
    [[ -n "$owner" ]] && echo -e "\033[1;33mDetectado: \033[1;37m$owner\033[0m"
    echo -e "\033[1;37mElija otro puerto o libere ese servicio antes de continuar.\033[0m"
}
v2ray_unit_name() {
    local port="$1"
    if systemctl list-unit-files "v2ray@${port}.service" >/dev/null 2>&1; then
    echo "v2ray@${port}"
    elif systemctl list-unit-files "xray@${port}.service" >/dev/null 2>&1; then
    echo "xray@${port}"
    else
    echo "v2ray@${port}"
    fi
}
v2ray_config_path_for_port() {
    local port="$1" cfg
    for cfg in "/root/TunnelCore/v2ray/conf/config.${port}.json" "/usr/local/etc/xray/config-${port}.json" "/usr/local/etc/xray/config.${port}.json"; do
    [[ -s "$cfg" ]] && echo "$cfg" && return 0
    done
    echo "/root/TunnelCore/v2ray/conf/config.${port}.json"
}
v2ray_selected_unit() {
    local port="$1" core="${2:-v2ray}"
    [[ "$core" == "xray" ]] && echo "xray@${port}" || echo "v2ray@${port}"
}
v2ray_core_for_port() {
    local port="$1" core
    core="$(awk -F'|' -v p="$port" '$1 == p {print $10; exit}' /etc/SSHPlus/v2ray/configs.db 2>/dev/null)"
    [[ "$core" == "xray" ]] && echo "xray" || echo "v2ray"
}
v2ray_ensure_template_service() {
    mkdir -p /etc/systemd/system
    cat >/etc/systemd/system/v2ray@.service <<'EOF'
[Unit]
Description=v2ray Service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/root/TunnelCore/v2ray/bin/v2ray/v2ray run -config /root/TunnelCore/v2ray/conf/config.%i.json
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    cat >/etc/systemd/system/xray@.service <<'EOF'
[Unit]
Description=xray Service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config-%i.json
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1 || true
}
v2ray_ports_configured() {
    local cfg
    {
    awk -F'|' '{if($1 ~ /^[0-9]+$/) print $1}' /etc/SSHPlus/v2ray/configs.db 2>/dev/null
    for cfg in /usr/local/etc/xray/config-*.json; do
    [[ -f "$cfg" ]] || continue
    basename "$cfg" | sed -E 's/^config-([0-9]+)\.json$/\1/'
    done
    for cfg in /usr/local/etc/xray/config.*.json /root/TunnelCore/v2ray/conf/config.*.json; do
    [[ -f "$cfg" ]] || continue
    basename "$cfg" | sed -E 's/^config\.([0-9]+)\.json$/\1/'
    done
    systemctl list-units 'v2ray@*.service' 'xray@*.service' --all --no-legend 2>/dev/null | awk '{print $1}' | grep -E '^(v2ray|xray)@[0-9]+\.service$' | sed -E 's/^(v2ray|xray)@([0-9]+)\.service$/\2/'
    systemctl list-unit-files 'v2ray@*.service' 'xray@*.service' --no-legend 2>/dev/null | awk '{print $1}' | grep -E '^(v2ray|xray)@[0-9]+\.service$' | sed -E 's/^(v2ray|xray)@([0-9]+)\.service$/\2/'
    } | sed '/^[[:space:]]*$/d' | sort -n | uniq
}
tc_xray_status_mark() {
    if v2ray_service_running; then
    printf '\033[1;32mo\033[0m'
    else
    printf '\033[1;31mx\033[0m'
    fi
}
v2ray_install_line() {
    local msg="$1" rc="${2:-0}"
    if [[ "$rc" = "0" ]]; then
    printf "\033[1;37m%-34s\033[1;32mOK\033[0m\n" "$msg"
    else
    printf "\033[1;37m%-34s\033[1;31mFAIL\033[0m\n" "$msg"
    fi
}
v2ray_random_name() {
    tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 6 || date +%s | tail -c 7
}
v2ray_random_path() {
    local rnd
    rnd="$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 8 || date +%s)"
    echo "/${rnd}/"
}
v2ray_ensure_local_cert() {
    local domain="${1:-local}" cert_dir="/root/TunnelCore/certificados/local"
    mkdir -p "$cert_dir"
    if [[ ! -s "${cert_dir}/local.crt" || ! -s "${cert_dir}/local.key" ]]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
      -keyout "${cert_dir}/local.key" \
      -out "${cert_dir}/local.crt" \
      -subj "/CN=${domain}" >/dev/null 2>&1 || return 1
    fi
    return 0
}
v2ray_normalize_inbound_json() {
    local inbound_json="$1" tls="$2" network="$3" host="$4" path="$5" tag="$6" proto="$7" sni="${8:-}" tmp
    [[ -z "$sni" ]] && sni="$host"
    tmp="${inbound_json}.tmp"
    jq --arg tls "$tls" --arg network "$network" --arg host "$host" --arg path "$path" --arg tag "$tag" --arg proto "$proto" --arg sni "$sni" '
      .tag = $tag |
      (if ((.settings.clients? | type) == "array") then
        .settings.clients |= map(
          if (.id?) then
            . + {email: (.email // $tag), level: (.level // 0)}
          else
            .
          end
        )
      else . end) |
      .domain = "local" |
      .streamSettings.security = $tls |
      (if $tls == "tls" then
        .streamSettings.tlsSettings = ({
          certificates: [
            {
              certificateFile: "/root/TunnelCore/certificados/local/local.crt",
              keyFile: "/root/TunnelCore/certificados/local/local.key"
            }
          ]
        } + (if $network == "xhttp" then {alpn: ["h2"]} else {} end))
      else
        del(.streamSettings.tlsSettings)
      end) |
      (if $network == "ws" then
        .streamSettings.wsSettings = ((.streamSettings.wsSettings // {}) + {
          headers: {Host: $host},
          path: $path
        })
      else . end) |
      (if $network == "h2" then
        .streamSettings.httpSettings = ((.streamSettings.httpSettings // {}) + {
          path: $path
        }) | del(.streamSettings.h2Settings)
      else . end) |
      (if $network == "grpc" then
        .streamSettings.grpcSettings = ((.streamSettings.grpcSettings // {}) + {
          serviceName: $path
        })
      else . end) |
      (if $network == "xhttp" then
        .streamSettings.xhttpSettings = ((.streamSettings.xhttpSettings // {}) + {
          path: $path,
          mode: (.streamSettings.xhttpSettings.mode // "packet-up")
        })
      else . end)
    ' "$inbound_json" > "$tmp" && mv "$tmp" "$inbound_json"
}
v2ray_wizard_screen() {
    local name="$1" type="$2" port="$3" proto="$4" network="$5" host="$6" path="$7" tls="$8"
    clear
    v2ray_title "INSTALAR V2RAY"
    [[ -n "$name" ]] && printf "\033[1;33mNOMBRE:\033[0m \033[1;37m%s\033[0m\n" "$name" && v2ray_line
    [[ -n "$type" ]] && printf "\033[1;33mTIPO:\033[0m \033[1;37m%s\033[0m\n" "$type" && v2ray_line
    [[ -n "$port" ]] && printf "\033[1;33mPUERTO:\033[0m \033[1;37m%s\033[0m\n" "$port" && v2ray_line
    [[ -n "$proto" ]] && printf "\033[1;33mPROTOCOLO:\033[0m \033[1;37m%s\033[0m\n" "$proto" && v2ray_line
    [[ -n "$network" ]] && printf "\033[1;33mRED:\033[0m \033[1;37m%s\033[0m\n" "$network" && v2ray_line
    [[ -n "$host" ]] && printf "\033[1;33mHOST WEBSOCKET:\033[0m \033[1;37m%s\033[0m\n" "$host" && v2ray_line
    [[ -n "$path" ]] && printf "\033[1;33mPATH:\033[0m \033[1;37m%s\033[0m\n" "$path" && v2ray_line
    [[ -n "$tls" ]] && printf "\033[1;33mTLS:\033[0m \033[1;37m%s\033[0m\n" "$tls" && v2ray_line
}
v2ray_install_wizard() {
    local name default_name type type_label port proto proto_label network network_label host path default_path tls tls_label sni opt uuid password method cfg port_cfg inbound_json test_log ext_port domain
    default_name="$(v2ray_random_name)"
    v2ray_wizard_screen
    echo -ne "${SSHPlus_DARK_GREEN}NOMBRE: [${default_name}]:${SCOLOR} "
    read name
    [[ -z "$name" ]] && name="$default_name"
    name="$(printf '%s' "$name" | sed -e 's/[^a-zA-Z0-9_.-]//g')"
    [[ -z "$name" ]] && name="$default_name"

    v2ray_wizard_screen "$name"
    v2ray_opt "1" "V2RAY"
    v2ray_opt "2" "XRAY"
    v2ray_line
    echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} "
    read opt
    case "$opt" in
      1) type="v2ray"; type_label="V2RAY" ;;
      2) type="xray"; type_label="XRAY" ;;
      *) echo -e "\033[1;31mOpcion no valida.\033[0m"; pausa_v2ray; return 1 ;;
    esac

    while true; do
    v2ray_wizard_screen "$name" "$type_label"
    echo -ne "${SSHPlus_DARK_GREEN}INGRESA PUERTO:${SCOLOR} "
    read port
    [[ -z "$port" ]] && port="80"
    if ! v2ray_valid_port "$port"; then
    echo -e "\033[1;31mPuerto no valido. Use 1-65535.\033[0m"
    sleep 1
    continue
    fi
    if v2ray_port_in_use_by_other "$port" "/usr/local/etc/xray/config-${port}.json"; then
    echo -e " \033[1;31mEN USO!\033[0m"
    sleep 1
    continue
    fi
    break
    done

    v2ray_wizard_screen "$name" "$type_label" "$port"
    v2ray_opt "1" "VMESS"
    v2ray_opt "2" "VLESS"
    v2ray_opt "3" "SOCK"
    v2ray_opt "4" "TROJAN"
    v2ray_opt "5" "HYSTERIA2 (no disponible)"
    v2ray_line
    echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} "
    read opt
    case "$opt" in
      1) proto="vmess"; proto_label="VMESS" ;;
      2) proto="vless"; proto_label="VLESS" ;;
      3) proto="socks"; proto_label="SOCK" ;;
      4) proto="trojan"; proto_label="TROJAN" ;;
      5) echo -e "\033[1;33mHYSTERIA2 aparece en el menu, pero aun no se configura desde V2Ray/Xray.\033[0m"; pausa_v2ray; return 1 ;;
      *) echo -e "\033[1;31mOpcion no valida.\033[0m"; pausa_v2ray; return 1 ;;
    esac

    v2ray_wizard_screen "$name" "$type_label" "$port" "$proto_label"
    v2ray_opt "1" "RED TCP"
    v2ray_opt "2" "RED GRPC"
    v2ray_opt "3" "RED WEBSOCKET"
    if [[ "$type" == "xray" && ( "$proto" == "vless" || "$proto" == "vmess" || "$proto" == "trojan" ) ]]; then
    v2ray_opt "4" "RED XHTTP"
    else
    v2ray_opt "4" "RED H2 (HTTP2)"
    v2ray_opt "5" "RED HYSTERIA2"
    fi
    v2ray_line
    echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} "
    read opt
    case "$opt" in
      1) network="tcp"; network_label="TCP" ;;
      2) network="grpc"; network_label="GRPC" ;;
      3) network="ws"; network_label="WEBSOCKET" ;;
      4)
        if [[ "$type" == "xray" && ( "$proto" == "vless" || "$proto" == "vmess" || "$proto" == "trojan" ) ]]; then
        network="xhttp"; network_label="XHTTP"
        else
        network="h2"; network_label="H2 (HTTP2)"
        fi
        ;;
      5)
        if [[ "$type" == "xray" && ( "$proto" == "vless" || "$proto" == "vmess" || "$proto" == "trojan" ) ]]; then
        echo -e "\033[1;31mOpcion no valida.\033[0m"
        else
        echo -e "\033[1;33mRED HYSTERIA2 aparece en el menu, pero aun no esta disponible aqui.\033[0m"
        fi
        pausa_v2ray
        return 1
        ;;
      *) echo -e "\033[1;31mOpcion no valida.\033[0m"; pausa_v2ray; return 1 ;;
    esac

    if [[ "$network" == "ws" ]]; then
    v2ray_wizard_screen "$name" "$type_label" "$port" "$proto_label" "$network_label"
    echo -ne "${SSHPlus_DARK_GREEN}HOST WEBSOCKET / BUG HOST:${SCOLOR} "
    read host
    host="$(printf '%s' "$host" | tr -d '"\\[:space:]')"
    fi
    if [[ "$network" == "ws" || "$network" == "h2" || "$network" == "xhttp" ]]; then
    default_path="$(v2ray_random_path)"
    v2ray_wizard_screen "$name" "$type_label" "$port" "$proto_label" "$network_label" "$host"
    echo -ne "${SSHPlus_DARK_GREEN}PATH [${default_path}]:${SCOLOR} "
    read path
    [[ -z "$path" ]] && path="$default_path"
    path="$(printf '%s' "$path" | tr -d '"\\[:space:]')"
    [[ "$path" != /* ]] && path="/$path"
    elif [[ "$network" == "grpc" ]]; then
    default_path="grpc"
    v2ray_wizard_screen "$name" "$type_label" "$port" "$proto_label" "$network_label"
    echo -ne "${SSHPlus_DARK_GREEN}SERVICE NAME GRPC [${default_path}]:${SCOLOR} "
    read path
    [[ -z "$path" ]] && path="$default_path"
    path="$(printf '%s' "$path" | tr -d '"\\[:space:]')"
    else
    path=""
    fi

    v2ray_wizard_screen "$name" "$type_label" "$port" "$proto_label" "$network_label" "$host" "$path"
    v2ray_opt "1" "TLS ACTIVAR"
    v2ray_opt "2" "TLS DESACTIVADO"
    v2ray_line
    echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} "
    read opt
    case "$opt" in
      1) tls="tls"; tls_label="ACTIVADO" ;;
      2) tls="none"; tls_label="DESACTIVADO" ;;
      *) echo -e "\033[1;31mOpcion no valida.\033[0m"; pausa_v2ray; return 1 ;;
    esac
    if [[ "$tls" == "tls" ]]; then
    v2ray_wizard_screen "$name" "$type_label" "$port" "$proto_label" "$network_label" "$host" "$path" "$tls_label"
    echo -ne "${SSHPlus_DARK_GREEN}DOMINIO/SNI TLS [${host:-obligatorio}]:${SCOLOR} "
    read sni
    [[ -z "$sni" ]] && sni="$host"
    sni="$(printf '%s' "$sni" | tr -d '"\\[:space:]')"
    if [[ -z "$sni" || "$sni" == "local" || "$sni" == "You-HostName.com" ]]; then
    echo -e "\033[1;31mPara TLS necesita un dominio/SNI real. Use TLS DESACTIVADO para conexion directa por IP.\033[0m"
    pausa_v2ray
    return 1
    fi
    [[ -z "$host" && "$network" == "xhttp" ]] && host="$sni"
    fi

    while true; do
    v2ray_wizard_screen "$name" "$type_label" "$port" "$proto_label" "$network_label" "$host" "$path" "$tls_label"
    v2ray_opt "1" "APLICAR"
    v2ray_opt "2" "VOLVER A CONFIGURAR"
    v2ray_opt "0" "CANCELAR"
    v2ray_line
    echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} "
    read opt
    case "$opt" in
      1) break ;;
      2) v2ray_install_wizard; return ;;
      0) return ;;
      *) echo -e "\033[1;31mOpcion no valida.\033[0m"; sleep 1 ;;
    esac
    done

    clear
    v2ray_wizard_screen "$name" "$type_label" "$port" "$proto_label" "$network_label" "$host" "$path" "$tls_label"
    if v2ray_install_core_only >/tmp/tunnelcore-v2ray-install.log 2>&1; then
    v2ray_install_line "Descargando v2ray-linux-64........." 0
    v2ray_install_line "Instalando v2ray..................." 0
    v2ray_install_line "Descargando Xray-linux-64.........." 0
    v2ray_install_line "Instalando xray...................." 0
    else
    cat /tmp/tunnelcore-v2ray-install.log 2>/dev/null
    v2ray_install_line "Instalando core V2Ray/Xray........." 1
    pausa_v2ray
    return 1
    fi

    uuid="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null)"
    password="$(tc_rand_string 16 2>/dev/null || tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"
    method="aes-128-gcm"
    mkdir -p /root/TunnelCore/v2ray/conf /root/TunnelCore/v2ray/log /usr/local/etc/xray /etc/SSHPlus/v2ray /etc/SSHPlus /var/log/xray
    if [[ "$tls" == "tls" ]]; then
    v2ray_ensure_local_cert "${sni:-local}" || { v2ray_install_line "Generando certificado TLS..........." 1; pausa_v2ray; return 1; }
    fi
    inbound_json="$(v2ray_write_inbound_json "$proto" "$network" "$tls" "$port" "$path" "$uuid" "$password" "$method" "" "${host}" "" "")"
    v2ray_normalize_inbound_json "$inbound_json" "$tls" "$network" "$host" "$path" "$name" "$proto" "$sni" || {
    rm -f "$inbound_json"
    v2ray_install_line "Normalizando inbound................." 1
    pausa_v2ray
    return 1
    }
    if [[ "$type" == "xray" ]]; then
    port_cfg="/usr/local/etc/xray/config-${port}.json"
    else
    port_cfg="/root/TunnelCore/v2ray/conf/config.${port}.json"
    fi
    jq -n --slurpfile inbound "$inbound_json" '{
      "log": {
        "access": "/root/TunnelCore/v2ray/log/access.log",
        "error": "/root/TunnelCore/v2ray/log/error.log",
        "loglevel": "none"
      },
      "stats": {},
      "api": {
        "tag": "api",
        "services": [
          "HandlerService",
          "LoggerService",
          "StatsService"
        ]
      },
      "policy": {
        "levels": {
          "0": {
            "statsUserDownlink": true,
            "statsUserUplink": true
          }
        },
        "system": {
          "statsInboundDownlink": true,
          "statsInboundUplink": true,
          "statsOutboundDownlink": true,
          "statsOutboundUplink": true
        }
      },
      "inbounds": [
        $inbound[0],
        {
          "listen": "127.0.0.1",
          "port": (10000 + $inbound[0].port),
          "protocol": "dokodemo-door",
          "settings": {
            "address": "127.0.0.1"
          },
          "tag": "api"
        }
      ],
      "outbounds": [
        {
          "protocol": "freedom",
          "settings": {}
        },
        {
          "protocol": "blackhole",
          "settings": {},
          "tag": "block"
        }
      ],
      "routing": {
        "rules": [
          {
            "ip": [
              "0.0.0.0/8",
              "10.0.0.0/8",
              "100.64.0.0/10",
              "169.254.0.0/16",
              "172.16.0.0/12",
              "192.0.0.0/24",
              "192.0.2.0/24",
              "192.168.0.0/16",
              "198.18.0.0/15",
              "198.51.100.0/24",
              "203.0.113.0/24",
              "::1/128",
              "fc00::/7",
              "fe80::/10"
            ],
            "outboundTag": "block",
            "type": "field"
          },
          {
            "inboundTag": [
              "api"
            ],
            "outboundTag": "api",
            "type": "field"
          }
        ],
        "domainStrategy": "AsIs"
      }
    }' > "$port_cfg" || { rm -f "$inbound_json"; v2ray_install_line "Generando config.json..............." 1; pausa_v2ray; return 1; }
    if [[ "$type" == "xray" ]]; then
    ln -sf "$port_cfg" "/usr/local/etc/xray/config.${port}.json" 2>/dev/null || cp -f "$port_cfg" "/usr/local/etc/xray/config.${port}.json" 2>/dev/null || true
    cp -f "$port_cfg" "/root/TunnelCore/v2ray/conf/config.${port}.json" 2>/dev/null || true
    else
    cp -f "$port_cfg" "/usr/local/etc/xray/config-${port}.json" 2>/dev/null || true
    ln -sf "/usr/local/etc/xray/config-${port}.json" "/usr/local/etc/xray/config.${port}.json" 2>/dev/null || true
    fi
    rm -f "$inbound_json"
    test_log="/tmp/tunnelcore-xray-test.log"
    if [[ "$type" == "xray" ]]; then
    /usr/local/bin/xray run -test -config "$port_cfg" >"$test_log" 2>&1
    test_rc=$?
    else
    /root/TunnelCore/v2ray/bin/v2ray/v2ray test -config "$port_cfg" >"$test_log" 2>&1
    test_rc=$?
    fi
    if [[ "$test_rc" != "0" ]]; then
    v2ray_install_line "Validando config.json..............." 1
    sed -n '1,12p' "$test_log" 2>/dev/null
    pausa_v2ray
    return 1
    fi
    v2ray_install_line "systemctl daemon-reload............" 0
    v2ray_ensure_template_service
    systemctl disable --now xray >/dev/null 2>&1 || true
    unit="$(v2ray_selected_unit "$port" "$type")"
    if systemctl start "$unit" >/dev/null 2>&1; then
    v2ray_install_line "systemctl start ${unit}......." 0
    else
    v2ray_install_line "systemctl start ${unit}......." 1
    fi
    if systemctl enable "$unit" >/dev/null 2>&1; then
    v2ray_install_line "systemctl enable ${unit}......" 0
    else
    v2ray_install_line "systemctl enable ${unit}......" 1
    fi
    ext_port="$port"
    [[ "$tls" == "tls" ]] && ext_port="$port"
    domain="$host"
    [[ "$tls" == "tls" && -n "$sni" ]] && domain="$sni"
    [[ -z "$domain" || "$domain" == "local" || "$domain" == "You-HostName.com" ]] && domain="$(cat /etc/SSHPlus/IP 2>/dev/null || cat /etc/IP 2>/dev/null || v2ray_public_ip)"
    grep -v "^${port}|" /etc/SSHPlus/v2ray/configs.db 2>/dev/null > /etc/SSHPlus/v2ray/configs.db.tmp || true
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$port" "$name" "$proto" "$network" "$tls" "$domain" "$path" "$ext_port" "$sni" "$type" >> /etc/SSHPlus/v2ray/configs.db.tmp
    mv -f /etc/SSHPlus/v2ray/configs.db.tmp /etc/SSHPlus/v2ray/configs.db
    grep -q "$uuid" /etc/SSHPlus/RegV2ray 2>/dev/null || echo "  $uuid | $name | $(date '+%Y-%m-%d' -d '+365 days' 2>/dev/null || date '+%Y-%m-%d') " >> /etc/SSHPlus/RegV2ray
    v2ray_line
    echo -e "\033[1;33m> PRESIONE ENTER PARA CONTINUAR...\033[0m"
    read enter
    return 0
}
v2ray_show_info() {
    local cfg
    if command -v v2ray >/dev/null 2>&1; then
    v2ray info
    return 0
    fi
    cfg="$(v2ray_config_file)"
    [[ -z "$cfg" ]] && echo -e "\033[1;31mNo se encontro config.json de V2Ray/Xray.\033[0m" && return 1
    echo -e "\033[1;33mComando v2ray no disponible; mostrando puertos desde config.json.\033[0m"
    if v2ray_require_jq; then
    jq -r '.inbounds[]? | "PUERTO: \(.port) | PROTOCOLO: \(.protocol // "desconocido") | RED: \(.streamSettings.network // "tcp")"' "$cfg"
    else
    grep -E '"port"|"protocol"|"network"' "$cfg"
    fi
}
msg01='\033[1;37m\033[1;33mUsuario vacio\033[0m'
msg02='\033[1;37m\033[1;33mNombre muy corto (MIN: 2 caracteres)\033[0m'
msg03='\033[1;37m\033[1;33mNombre muy largo (MAX: 20 caracteres)\033[0m'
msg04='\033[1;37m\033[1;33mContrasena vacia\033[0m'
msg05='\033[1;37m\033[1;33mContrasena muy corta\033[0m'
msg06='\033[1;37m\033[1;33mContrasena muy larga\033[0m'
msg07='\033[1;37m\033[1;33mDuracion vacia\033[0m'
msg08='\033[1;37m\033[1;33mDuracion no valida, use solo numeros\033[0m'
msg09='\033[1;37m\033[1;33mDuracion maxima un ano\033[0m'
msg11='\033[1;37m\033[1;33mLimite vacio\033[0m'
msg12='\033[1;37m\033[1;33mLimite no valido, use solo numeros\033[0m'
msg13='\033[1;37m\033[1;33mLimite maximo 999\033[0m'
msg14='\033[1;37m\033[1;33mEl usuario ya existe\033[0m'
msg15='\033[1;37m\033[1;33m(Solo numeros) GB = Min: 1gb Max: 1000gb\033[0m'
msg16='\033[1;37m\033[1;33m(Solo numeros)\033[0m'
msg17='\033[1;37m\033[1;33m(Sin datos - Para cancelar pulse CTRL + C)\033[0m'
    err_fun () {
        case $1 in
        1)msg -verm "$(fun_trans "Usuario vacio")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
        2)msg -verm "$(fun_trans "Nombre muy corto (MIN: 2 caracteres)")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
        3)msg -verm "$(fun_trans "Nombre muy largo (MAX: 20 caracteres)")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
        4)msg -verm "$(fun_trans "Contrasena vacia")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
        5)msg -verm "$(fun_trans "Contrasena muy corta")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
        6)msg -verm "$(fun_trans "Contrasena muy larga")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
        7)msg -verm "$(fun_trans "Duracion vacia")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
        8)msg -verm "$(fun_trans "Duracion no valida, use solo numeros")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
        9)msg -verm "$(fun_trans "Duracion maxima un ano")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
        11)msg -verm "$(fun_trans "Limite vacio")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
        12)msg -verm "$(fun_trans "Limite no valido, use solo numeros")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
        13)msg -verm "$(fun_trans "Limite maximo 999")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
        14)msg -verm "$(fun_trans "El usuario ya existe")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
	    15)msg -verm "$(fun_trans "(Solo numeros) GB = Min: 1gb Max: 1000gb")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
	    16)msg -verm "$(fun_trans "(Solo numeros)")"; sleep 2s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
	    17)msg -verm "$(fun_trans "(Sin datos - Para cancelar pulse CTRL + C)")"; sleep 4s; tput cuu1; tput dl1; tput cuu1; tput dl1;;
        esac
    }

    intallv2ray () {
    clear
    v2ray_title "INSTALAR V2RAY / XRAY"
    echo -e "\033[1;37mTunnelCore instalara Xray-core nativo para crear perfiles V2Ray/Xray.\033[0m"
    echo -e "\033[1;33mDespues de instalar podra elegir protocolo, puerto, red, host, path y TLS.\033[0m"
    v2ray_install_wizard
    return
    }

    v2ray_install_core_only() {
    local arch xray_asset v2ray_asset xray_url v2ray_url dep
    mkdir -p /root/TunnelCore/v2ray/bin/v2ray /root/TunnelCore/v2ray/bin/xray /root/TunnelCore/v2ray/conf /root/TunnelCore/v2ray/log /usr/local/etc/xray /etc/v2ray /etc/SSHPlus/v2ray /etc/SSHPlus /var/log/xray
    if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y unzip curl wget ca-certificates jq uuid-runtime openssl lsof libstdc++6 libcurl4-openssl-dev >/dev/null 2>&1 || true
    fi
    for dep in unzip jq openssl; do
    if ! command -v "$dep" >/dev/null 2>&1; then
    echo -e "\033[1;31mDependencia faltante: $dep\033[0m"
    return 1
    fi
    done
    if [[ -x /root/TunnelCore/v2ray/bin/v2ray/v2ray && -x /usr/local/bin/xray ]]; then
    echo -e "\033[1;32mV2Ray/Xray-core ya estan instalados.\033[0m"
    v2ray_ensure_template_service
    return 0
    fi
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo -e "\033[1;31mNecesita curl o wget para descargar Xray.\033[0m"
    return 1
    fi
    arch="$(uname -m)"
    case "$arch" in
    x86_64|amd64) v2ray_asset="v2ray-linux-64.zip"; xray_asset="Xray-linux-64.zip" ;;
    aarch64|arm64) v2ray_asset="v2ray-linux-arm64-v8a.zip"; xray_asset="Xray-linux-arm64-v8a.zip" ;;
    *) echo -e "\033[1;31mArquitectura no soportada: $arch\033[0m"; return 1 ;;
    esac
    v2ray_url="https://github.com/v2fly/v2ray-core/releases/latest/download/${v2ray_asset}"
    xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/${xray_asset}"
    cd /tmp || { echo -e "\033[1;31mNo se pudo acceder a /tmp\033[0m"; return 1; }
    rm -rf v2ray-install xray-install v2ray.zip xray.zip
    mkdir -p v2ray-install
    if [[ ! -x /root/TunnelCore/v2ray/bin/v2ray/v2ray ]]; then
    if command -v curl >/dev/null 2>&1; then
    curl -fL -o v2ray.zip "$v2ray_url"
    else
    wget -O v2ray.zip "$v2ray_url"
    fi
    [[ -s v2ray.zip ]] || { echo -e "\033[1;31mNo se pudo descargar V2Ray.\033[0m"; return 1; }
    unzip -o v2ray.zip -d v2ray-install >/dev/null 2>&1 || { echo -e "\033[1;31mNo se pudo descomprimir V2Ray.\033[0m"; return 1; }
    install -m 755 v2ray-install/v2ray /root/TunnelCore/v2ray/bin/v2ray/v2ray || { echo -e "\033[1;31mNo se pudo instalar V2Ray.\033[0m"; return 1; }
    ln -sf /root/TunnelCore/v2ray/bin/v2ray/v2ray /usr/local/bin/v2ray 2>/dev/null || true
    ln -sf /root/TunnelCore/v2ray/bin/v2ray/v2ray /usr/bin/v2ray 2>/dev/null || true
    fi
    mkdir -p xray-install
    if [[ ! -x /usr/local/bin/xray ]]; then
    if command -v curl >/dev/null 2>&1; then
    curl -fL -o xray.zip "$xray_url"
    else
    wget -O xray.zip "$xray_url"
    fi
    [[ -s xray.zip ]] || { echo -e "\033[1;31mNo se pudo descargar Xray.\033[0m"; return 1; }
    unzip -o xray.zip -d xray-install >/dev/null 2>&1 || { echo -e "\033[1;31mNo se pudo descomprimir Xray.\033[0m"; return 1; }
    install -m 755 xray-install/xray /usr/local/bin/xray || { echo -e "\033[1;31mNo se pudo instalar /usr/local/bin/xray.\033[0m"; return 1; }
    install -m 755 xray-install/xray /root/TunnelCore/v2ray/bin/xray/xray 2>/dev/null || true
    ln -sf /usr/local/bin/xray /usr/bin/xray 2>/dev/null || true
    fi
    [[ -s /usr/local/etc/xray/config.json ]] || cat >/usr/local/etc/xray/config.json <<'EOF'
{
  "log": { "loglevel": "warning" },
  "inbounds": [],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" }
  ]
}
EOF
    ln -sf /usr/local/etc/xray/config.json /etc/v2ray/config.json 2>/dev/null || true
    v2ray_ensure_template_service
    echo -e "\033[1;32mV2Ray/Xray-core instalados correctamente.\033[0m"
    return 0
    }

    intallv2ray_legacy () {
    if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y curl wget unzip ca-certificates jq >/dev/null 2>&1 || true
    fi
        if python3 -c 'import sys; exit(0 if sys.version_info < (3, 9) else 1)' 2>/dev/null; then
        curl -fsSL https://bootstrap.pypa.io/pip/3.8/get-pip.py | python3 >/dev/null 2>&1 || true
    fi
    pip3 install --upgrade v2ray_util >/dev/null 2>&1 || true

    source <(curl -sL https://multi.netlify.app/v2ray.sh) -k && source <(curl -sL https://multi.netlify.app/v2ray.sh)
    echo -e "\033[1;37m\033[1;33mInstalado correctamente!\033[0m"
    USRdatabase="/etc/SSHPlus/RegV2ray"
    [[ ! -e ${USRdatabase} ]] && touch ${USRdatabase}
    sort ${USRdatabase} | uniq > ${USRdatabase}tmp
    mv -f ${USRdatabase}tmp ${USRdatabase}
clear
    if ! command -v v2ray >/dev/null 2>&1; then
    echo -e "\033[1;31mEl instalador original no dejo disponible el comando v2ray.\033[0m"
    echo -e "\033[1;37mSe abrira el instalador Xray XHTTP local para crear una configuracion funcional.\033[0m"
    pausa_v2ray
    instalar_xray_xhttp
    return
    fi
    v2ray_title "ELIJA EL PROTOCOLO V2RAY"
    v2ray stream
clear
    linea_v2ray
    v2ray_title "INDIQUE EL PUERTO V2RAY [8443] o [443]"
    v2ray port 
clear
config_v2ray="$(v2ray_config_file)"
if [[ -z "$config_v2ray" ]]; then
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;31mNo se encontro config.json de V2Ray/Xray.\033[0m"
    echo -e "\033[1;37mLa instalacion base no genero el archivo de configuracion.\033[0m"
    echo -e "\033[1;37mUse REINSTALAR V2RAY o CONFIGURACION DE V2RAY > INSTALAR XRAY XHTTP.\033[0m"
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

fi
v2ray_ensure_legacy_config "$config_v2ray"
    linea_v2ray
    v2ray_title "INFORMACION DE CUENTA"
    v2ray_show_info
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    }

    v2ray_restart_service() {
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

    v2ray_select_port() {
    local cfg="$1" title="$2" ports count opt
    ports="$(jq -r '.inbounds[]? | select((.settings.clients? | type) == "array") | .port' "$cfg")"
    count="$(echo "$ports" | sed '/^$/d' | wc -l)"
    [[ "$count" -lt 1 ]] && return 1
    v2ray_title "$title" >&2
    echo "$ports" | sed '/^$/d' | nl -w1 -s' | ' | while IFS= read -r line; do
    printf "%b[%s]\033[0m \033[1;37m>\033[0m \033[1;37mPUERTO %s\033[0m\n" "$SSHPlus_NUM" "${line%% | *}" "${line#* | }" >&2
    done
    v2ray_opt "0" "CANCELAR" >&2
    v2ray_line >&2
    while true; do
    echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} " >&2
    read opt
    [[ "$opt" = "0" ]] && return 2
    [[ "$opt" =~ ^[0-9]+$ ]] && [[ "$opt" -ge 1 ]] && [[ "$opt" -le "$count" ]] && {
      echo "$ports" | sed '/^$/d' | sed -n "${opt}p"
      return 0
    }
    echo -e "\033[1;31mOpcion no valida!\033[0m" >&2
    sleep 1
    done
    }

    v2ray_set_websocket() {
    local cfg path host tmp
    clear
    v2ray_title "ACTIVAR WEBSOCKET V2RAY"
    cfg="$(v2ray_config_file)"
    [[ -z "$cfg" ]] && echo -e "\033[1;31mNo se encontro config.json de V2Ray/Xray.\033[0m" && pausa_v2ray && ajustes_v2ray
    v2ray_ensure_legacy_config "$cfg"
    cfg="/etc/v2ray/config.json"
    echo -ne "${SSHPlus_DARK_GREEN}PATH WEBSOCKET [Enter = /]:${SCOLOR} " && read path
    [[ -z "$path" ]] && path="/"
    [[ "$path" != /* ]] && path="/$path"
    echo -ne "${SSHPlus_DARK_GREEN}HOST/DOMINIO [opcional]:${SCOLOR} " && read host
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
    else
    echo -e "\033[1;31mjq no esta instalado; use MODIFICAR JSON V2RAY o instale jq.\033[0m"
    pausa_v2ray
    ajustes_v2ray
    fi
    v2ray_restart_service
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;32mWebSocket aplicado correctamente.\033[0m"
    echo -e "${SSHPlus_DARK_GREEN}PATH:${SCOLOR} \033[1;37m$path\033[0m"
    [[ -n "$host" ]] && echo -e "${SSHPlus_DARK_GREEN}HOST:${SCOLOR} \033[1;37m$host\033[0m"
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    pausa_v2ray
    ajustes_v2ray
    }

    protocolv2ray () {
    local opt
    clear
    v2ray_title "CAMBIAR PROTOCOLO V2RAY"
    v2ray_opt "1" "Abrir selector original"
    v2ray_opt "3" "WebSocket"
    v2ray_line
    v2ray_opt "0" "VOLVER"
    v2ray_line
    echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} " && read opt
    case "$opt" in
    3 | 03) v2ray_set_websocket ;;
    1 | 01)
    if ! command -v v2ray >/dev/null 2>&1; then
    echo -e "\033[1;31mEl selector original requiere el comando v2ray.\033[0m"
    echo -e "\033[1;37mPara Xray use MODIFICAR JSON, MODIFICAR PATH o AGREGAR PUERTO.\033[0m"
    pausa_v2ray
    ajustes_v2ray
    fi
    v2ray stream
    v2ray_line
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    ;;
    0 | 00) ajustes_v2ray ;;
    *) echo -e "\033[1;31mOpcion no valida!\033[0m"; sleep 2; protocolv2ray ;;
    esac
    }
    tls () {
    clear
    v2ray_title "Activar o desactivar TLS"
    if ! command -v v2ray >/dev/null 2>&1; then
    echo -e "\033[1;31mLa opcion TLS original requiere el comando v2ray.\033[0m"
    echo -e "\033[1;37mEn Xray edite TLS desde MODIFICAR JSON V2RAY.\033[0m"
    pausa_v2ray
    ajustes_v2ray
    fi
    v2ray tls
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    }
    portv () {
    v2ray_title "CAMBIAR PUERTO V2RAY"
    if ! command -v v2ray >/dev/null 2>&1; then
    echo -e "\033[1;31mLa opcion cambiar puerto original requiere el comando v2ray.\033[0m"
    echo -e "\033[1;37mUse AGREGAR PUERTO V2RAY o MODIFICAR JSON V2RAY para Xray.\033[0m"
    pausa_v2ray
    ajustes_v2ray
    fi
    v2ray port
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    }

    agregar_puerto_v2ray() {
    local cfg tmp port base_port
    clear
    v2ray_title "AGREGAR PUERTO V2RAY"
    cfg="$(v2ray_config_file)"
    [[ -z "$cfg" ]] && echo -e "\033[1;31mNo se encontro config.json de V2Ray/Xray.\033[0m" && pausa_v2ray && ajustes_v2ray
    v2ray_ensure_legacy_config "$cfg"
    cfg="/etc/v2ray/config.json"
    if ! v2ray_require_jq; then
    echo -e "\033[1;31mjq no esta instalado; no se puede modificar el JSON de forma segura.\033[0m"
    pausa_v2ray
    ajustes_v2ray
    fi
    base_port="$(jq -r '.inbounds[]? | select((.settings.clients? | type) == "array") | .port' "$cfg" | sed '/^$/d' | head -1)"
    [[ -z "$base_port" ]] && echo -e "\033[1;31mNo hay inbound base con settings.clients para duplicar.\033[0m" && pausa_v2ray && ajustes_v2ray
    echo -e "\033[1;33mPuerto base detectado: \033[1;37m$base_port\033[0m"
    while true; do
    echo -ne "${SSHPlus_DARK_GREEN}NUEVO PUERTO V2RAY:${SCOLOR} " && read port
    [[ -z "$port" ]] && echo -e "$msg17" && continue
    if ! v2ray_valid_port "$port"; then
    echo -e "\033[1;31mPuerto no valido. Use 1-65535.\033[0m"
    continue
    fi
    if v2ray_port_in_use_by_other "$port" "$cfg"; then
    v2ray_warn_port_busy "$port"
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
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg" || {
      rm -f "$tmp"
      echo -e "\033[1;31mNo se pudo agregar el nuevo puerto al config.json.\033[0m"
      pausa_v2ray
      ajustes_v2ray
    }
    jq -e --argjson port "$port" '.inbounds[]? | select(.port == $port)' "$cfg" >/dev/null || {
      echo -e "\033[1;31mNo se pudo confirmar el nuevo puerto en config.json.\033[0m"
      pausa_v2ray
      ajustes_v2ray
    }
    v2ray_restart_service
    echo -e "\033[1;32mPuerto agregado correctamente.\033[0m"
    echo -e "\033[1;33mNuevo puerto: \033[1;37m$port\033[0m"
    pausa_v2ray
    ajustes_v2ray
    }
    stats () {
    v2ray_title "ESTADISTICAS DE CONSUMO"
    v2ray stats
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    }
    unistallv2 () {
    local unit
    source <(curl -sL https://multi.netlify.app/v2ray.sh) --remove > /dev/null 2>&1 || true
    for unit in $(systemctl list-units 'v2ray@*.service' 'xray@*.service' --all --no-legend 2>/dev/null | awk '{print $1}'); do
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
    done
    for unit in $(systemctl list-unit-files 'v2ray@*.service' 'xray@*.service' --no-legend 2>/dev/null | awk '{print $1}'); do
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
    done
    systemctl stop xray v2ray >/dev/null 2>&1 || true
    systemctl disable xray v2ray >/dev/null 2>&1 || true
    pkill -x xray >/dev/null 2>&1 || true
    pkill -x v2ray >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/xray.service /etc/systemd/system/v2ray.service /etc/systemd/system/xray@.service /etc/systemd/system/v2ray@.service >/dev/null 2>&1
    rm -f /usr/local/bin/xray /usr/bin/xray /bin/xray /usr/local/bin/v2ray /usr/bin/v2ray /bin/v2ray >/dev/null 2>&1
    rm -rf /usr/local/etc/xray /usr/local/etc/v2ray /etc/xray /etc/v2ray /var/log/xray >/dev/null 2>&1
    rm -rf /root/TunnelCore/v2ray /root/TunnelCore/certificados/local >/dev/null 2>&1
    rm -rf /etc/SSHPlus/v2ray /etc/SSHPlus/RegV2ray > /dev/null 2>&1
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed >/dev/null 2>&1 || true
    echo -e "\n\033[1;32mV2RAY ELIMINADO CORRECTAMENTE.\033[0m"
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    }
    infocuenta () {
    v2ray_title "INFORMACION DE CUENTA"
    v2ray_show_info
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    }
    addusr () {
    clear
    if [[ -s /etc/SSHPlus/v2ray/configs.db ]]; then
    v2ray_add_user_port_config
    return
    fi
    v2ray_title "ANADIR USUARIO | UUID V2RAY"
    local cfg tmp
    cfg="$(v2ray_config_file)"
    [[ -z "$cfg" ]] && echo -e "\033[1;31mNo se encontro config.json de V2Ray/Xray.\033[0m" && pausa_v2ray && return
    v2ray_ensure_legacy_config "$cfg"
    cfg="/etc/v2ray/config.json"
    if ! v2ray_require_jq; then
        echo -e "\033[1;31mjq no esta instalado; no se puede modificar el JSON de forma segura.\033[0m"
        echo -e "\033[1;37mInstale jq y vuelva a intentar crear el usuario V2Ray.\033[0m"
        pausa_v2ray
        return
    fi

    # 1. Nombre de usuario
    while true; do
        v2ray_prompt "NOMBRE DE USUARIO:"
        read nick
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

    # 2. Elegir Protocolo (VMess o VLESS)
    local proto_choice="1" proto_name="VMess" proto_tag="vmess"
    while true; do
        echo ""
        echo -e "\033[1;37mSELECCIONAR PROTOCOLO:\033[0m"
        v2ray_opt "1" "VMess"
        v2ray_opt "2" "VLESS"
        v2ray_prompt "Opcion:" && read proto_choice
        case "$proto_choice" in
            1) proto_name="VMess"; proto_tag="vmess"; break ;;
            2) proto_name="VLESS"; proto_tag="vless"; break ;;
            *) echo -e "\033[1;31mOpcion no valida!\033[0m" ;;
        esac
    done

    # 3. Elegir Puerto (de los puertos configurados en el V2Ray)
    mapfile -t v2_ports < <(jq -r '.inbounds[]? | select((.settings.clients? | type) == "array") | .port' "$cfg" 2>/dev/null | sed '/^$/d' | sort -n | uniq)
    local selected_port="" selected_ports_disp="" apply_all=false
    if [[ "${#v2_ports[@]}" -eq 0 ]]; then
        v2ray_prompt "PUERTO V2RAY (ej: 80, 443, 8080):" && read selected_port
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
            v2ray_prompt "Opcion:" && read p_opt
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
                echo -e "\033[1;31mOpcion no valida!\033[0m"
            fi
        done
    fi

    local inbound_proto inbound_network
    inbound_proto="$(jq -r --argjson p "${selected_port:-0}" '.inbounds[]? | select(.port == $p) | .protocol // ""' "$cfg" 2>/dev/null | head -1)"
    inbound_network="$(jq -r --argjson p "${selected_port:-0}" '.inbounds[]? | select(.port == $p) | .streamSettings.network // "tcp"' "$cfg" 2>/dev/null | head -1)"
    [[ -z "$inbound_network" || "$inbound_network" == "null" ]] && inbound_network="tcp"
    if [[ "$inbound_proto" == "vless" && "$proto_tag" != "vless" ]]; then
        proto_name="VLESS"
        proto_tag="vless"
        echo -e "\033[1;33mEl puerto seleccionado es VLESS; se ajusto el protocolo automaticamente.\033[0m"
    elif [[ "$inbound_proto" == "vmess" && "$proto_tag" != "vmess" ]]; then
        proto_name="VMess"
        proto_tag="vmess"
        echo -e "\033[1;33mEl puerto seleccionado es VMess; se ajusto el protocolo automaticamente.\033[0m"
    fi

    # 4. Configurar UUID (Aleatorio o Manual)
    while true; do
        echo ""
        echo -e "\033[1;37mCONFIGURAR UUID / ID:\033[0m"
        v2ray_opt "1" "Generar automaticamente (Aleatorio)"
        v2ray_opt "2" "Ingresar manualmente"
        v2ray_prompt "Opcion:" && read uuidopc
        case "$uuidopc" in
            1)
                UUID="$(command -v uuidgen >/dev/null 2>&1 && uuidgen || cat /proc/sys/kernel/random/uuid 2>/dev/null)"
                [[ -z "$UUID" ]] && UUID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null)"
                while grep -q "$UUID" /etc/SSHPlus/RegV2ray 2>/dev/null || grep -q "$UUID" "$cfg" 2>/dev/null; do
                    UUID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null)"
                done
                break
                ;;
            2)
                v2ray_prompt "UUID:" && read UUID
                [[ -z "$UUID" ]] && echo -e "$msg17" && continue
                if ! v2ray_valid_uuid "$UUID"; then
                    echo -e "\033[1;31mUUID no valido.\033[0m"
                    continue
                fi
                break
                ;;
            *)
                echo -e "\033[1;31mOpcion no valida!\033[0m"
                ;;
        esac
    done

    # 5. Activar TLS / Modo de conexion
    local tls_opt="1" tls_mode="none" add_host="" host_header="" sni_host="" ext_port="$selected_port"
    local cur_domain="$(cat /etc/SSHPlus/v2ray/domain 2>/dev/null || cat /etc/xray/domain 2>/dev/null || cat /etc/v2ray/domain 2>/dev/null || echo "")"
    local vps_ip="$(cat /etc/IP 2>/dev/null || echo "$IP")"

    while true; do
        echo ""
        echo -e "\033[1;37mMODO DE CONEXION / SEGURIDAD TLS:\033[0m"
        v2ray_opt "1" "DIRECTO A IP (Sin TLS / HTTP WS - Puerto $selected_port)"
        v2ray_opt "2" "CLOUDFLARE CDN (Con TLS / Dominio - Puerto 443 + SNI Bug)"
        v2ray_prompt "Opcion:" && read tls_opt
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
                # Dominio / Cloudflare Add
                if [[ -n "$cur_domain" ]]; then
                    v2ray_prompt "DOMINIO / HOST ADD (actual: $cur_domain) [Enter para usar]:"
                    read user_domain
                    [[ -n "$user_domain" ]] && add_host="$user_domain" || add_host="$cur_domain"
                else
                    while true; do
                        v2ray_prompt "DOMINIO / HOST ADD (ej: midominio.com):"
                        read user_domain
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

                # SNI / Bug Host (ej: bug.operadora.com)
                echo ""
                v2ray_prompt "SNI / BUG HOST (ej: bug.operadora.com) [Enter para usar $add_host]:"
                read user_sni
                if [[ -n "$user_sni" ]]; then
                    sni_host="$user_sni"
                    host_header="$user_sni"
                else
                    sni_host="$add_host"
                    host_header="$add_host"
                fi
                break
                ;;
            *)
                echo -e "\033[1;31mOpcion no valida!\033[0m"
                ;;
        esac
    done

    # 6. Duracion en dias
    while true; do
        echo ""
        v2ray_prompt "DURACION DEL USUARIO (DIAS):" && read diasuser
        if [[ -z "$diasuser" ]]; then
            echo -e "$msg17" && continue
        elif [[ "$diasuser" != +([0-9]) ]]; then
            echo -e "$msg08" && continue
        elif [[ "$diasuser" -gt "360" ]]; then
            echo -e "$msg09" && continue
        fi
        break
    done

    local valid=$(date '+%C%y-%m-%d' -d " +$diasuser days")
    local datexp=$(date "+%F" -d " + $diasuser days")

    # 7. Agregar al config.json
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

    # 8. Registro y reinicio
    mkdir -p /etc/SSHPlus/v2ray
    if ! grep -q "$UUID.*$nick" /etc/SSHPlus/RegV2ray 2>/dev/null; then
        echo "  $UUID | $nick | $valid " >> /etc/SSHPlus/RegV2ray
    fi
    v2ray_restart_service

    # 9. Generar Enlace URI
    local path_ws="$(jq -r --argjson p "${selected_port:-80}" '.inbounds[]? | select(.port == $p) | .streamSettings.wsSettings.path // .streamSettings.xhttpSettings.path // ""' "$cfg" 2>/dev/null)"
    [[ -z "$path_ws" || "$path_ws" == "null" ]] && path_ws="$(jq -r '.inbounds[0].streamSettings.wsSettings.path // .inbounds[0].streamSettings.xhttpSettings.path // "/v2ray"' "$cfg" 2>/dev/null)"
    [[ -z "$path_ws" || "$path_ws" == "null" ]] && path_ws="/v2ray"

    local link_network="$inbound_network"
    [[ -z "$link_network" || "$link_network" == "null" ]] && link_network="ws"
    if [[ "$type" == "xray" && "$link_network" == "xhttp" && "$tls_mode" == "tls" ]]; then
        add_host="local"
        sni_host="local"
        host_header="You-HostName.com"
    fi
    local uri=""
    if [[ "$proto_tag" == "vmess" ]]; then
        local vmess_json
        local vmess_alpn="" vmess_fp="" vmess_mode=""
        if [[ "$link_network" == "xhttp" ]]; then
            vmess_mode="packet-up"
        fi
        if [[ "$tls_mode" == "tls" ]]; then
            vmess_fp="chrome"
            [[ "$link_network" == "xhttp" ]] && vmess_alpn="h2"
        fi
        vmess_json=$(cat <<EOF
{
  "v": "2",
  "ps": "$nick",
  "add": "${add_host}",
  "port": "${ext_port}",
  "id": "$UUID",
  "aid": "0",
  "scy": "auto",
  "net": "${link_network}",
  "type": "",
  "host": "${host_header}",
  "path": "${path_ws}",
  "tls": "${tls_mode}",
  "sni": "${sni_host}",
  "alpn": "${vmess_alpn}",
  "fp": "${vmess_fp}",
  "mode": "${vmess_mode}"
}
EOF
)
        local vmess_b64="$(printf '%s' "$vmess_json" | base64 -w 0 2>/dev/null || printf '%s' "$vmess_json" | base64 | tr -d '\n')"
        uri="vmess://${vmess_b64}"
    else
        local enc_path="$(v2ray_urlencode_path "$path_ws")"
        [[ -z "$link_network" || "$link_network" == "null" || "$link_network" == "tcp" ]] && link_network="ws"
        if [[ "$tls_mode" == "tls" ]]; then
            if [[ "$link_network" == "xhttp" ]]; then
                uri="vless://${UUID}@${add_host}:${ext_port}?encryption=none&type=xhttp&security=tls&sni=${sni_host}&host=${host_header}&path=${enc_path}&mode=packet-up#${nick}"
            else
                uri="vless://${UUID}@${add_host}:${ext_port}?type=${link_network}&security=tls&sni=${sni_host}&host=${host_header}&path=${enc_path}#${nick}"
            fi
        else
            if [[ "$link_network" == "xhttp" ]]; then
                uri="vless://${UUID}@${add_host}:${ext_port}?encryption=none&type=xhttp&security=none&path=${enc_path}&mode=packet-up#${nick}"
            else
                uri="vless://${UUID}@${add_host}:${ext_port}?type=${link_network}&security=none&path=${enc_path}#${nick}"
            fi
        fi
    fi

    # 10. Mostrar Ficha y URI
    clear
    v2ray_title "USUARIO V2RAY CREADO CON EXITO"
    v2ray_line
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "USUARIO:" "$nick"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "PROTOCOLO:" "$proto_name"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "PUERTO(S) VPS:" "$selected_ports_disp"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "PUERTO CONEXION:" "$ext_port"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "UUID / ID:" "$UUID"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "SEGURIDAD TLS:" "$tls_mode"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "SERVIDOR (ADD):" "$add_host"
    [[ "$tls_mode" == "tls" ]] && printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "SNI / BUG HOST:" "$sni_host"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s\033[0m\n" "PATH:" "$path_ws"
    printf "\033[1;32m%-22s\033[0m \033[1;37m%s (%s dias)\033[0m\n" "EXPIRA:" "$datexp" "$diasuser"
    v2ray_line
    echo -e "\033[1;33mENLACE URI (Copiar para importar):\033[0m\n"
    echo -e "\033[1;36m${uri}\033[0m\n"
    v2ray_line
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    }

    delusr () {
    clear
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
    printf "%b[%s]\033[0m \033[1;37m>\033[0m \033[1;37m%-20s\033[0m \033[1;33m%s\033[0m\n" "$SSHPlus_NUM" "$((i+1))" "${user_list[$i]}" "${uuid_list[$i]}"
    done
    v2ray_opt "0" "CANCELAR"
    v2ray_line
    while true; do
    echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} "
    read uuid_sel
    [[ "$uuid_sel" = "0" ]] && return
    [[ "$uuid_sel" =~ ^[0-9]+$ ]] && [[ "$uuid_sel" -ge 1 ]] && [[ "$uuid_sel" -le "${#uuid_list[@]}" ]] && break
    echo -e "\033[1;31mOpcion no valida!\033[0m"
    sleep 1
    done
    uuidel="${uuid_list[$((uuid_sel-1))]}"
    local nick_del="${user_list[$((uuid_sel-1))]}"
    linePre="${line_list[$((uuid_sel-1))]}"
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
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg" || {
      rm -f "$tmp"
      echo -e "\033[1;31mNo se pudo eliminar el UUID del config.json.\033[0m"
      pausa_v2ray

    }
    v2ray_restart_service
    else
    echo -e "\033[1;31mjq no esta instalado; se elimino solo el registro, no el config.json.\033[0m"
    fi
    fi
    echo ""
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\e[92m     USUARIO ${nick_del} ELIMINADO DE TODOS LOS PUERTOS "
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    }

    mosusr_kk() {
    clear
    v2ray_title "USUARIOS V2RAY REGISTRADOS"
    VPSsec=$(date +%s)
    if [[ ! -s /etc/SSHPlus/RegV2ray ]]; then
    echo -e "----- NINGUN USUARIO REGISTRADO -----"
    v2ray_line
    v2ray_opt "0" "VOLVER"
    v2ray_line
    echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} " && read enter

    fi
    printf "\033[1;37m%-36s %-14s %s\033[0m\n" "UUID" "USUARIO" "EXPIRA"
    printf "\033[1;37m------------------------------------------------------------\033[0m\n"
    while IFS='|' read -r uuid user expire; do
    uuid="$(echo "$uuid" | xargs)"
    user="$(echo "$user" | xargs)"
    expire="$(echo "$expire" | xargs)"
    [[ -z "$uuid" ]] && continue
    if [[ -n "$expire" ]]; then
    DataSec=$(date +%s --date="$expire" 2>/dev/null)
    if [[ -n "$DataSec" ]]; then
    [[ "$VPSsec" -gt "$DataSec" ]] && EXPTIME="\033[1;31mEXPIRADO\033[0m" || EXPTIME="\033[1;32m$(($(($DataSec - $VPSsec)) / 86400)) Dias\033[0m"
    else
    EXPTIME="\033[1;31mS/R\033[0m"
    fi
    else
    EXPTIME="\033[1;31mS/R\033[0m"
    fi
    printf "\033[1;33m%s\033[0m %b>\033[0m \033[1;37m%s\033[0m %b>\033[0m %b\n" "$uuid" "$SSHPlus_CYAN" "$user" "$SSHPlus_CYAN" "$EXPTIME"
    done < /etc/SSHPlus/RegV2ray
    v2ray_line
    v2ray_opt "0" "VOLVER"
    v2ray_line
    echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} " && read enter

    }
    lim_port () {
    clear 
    clear
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    v2ray_title "LIMITAR MB x PUERTO | UUID V2RAY"
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    ###VER
    estarts () {
    VPSsec=$(date +%s)
    local HOST="/etc/SSHPlus/v2ray/lisportt.log"
    local HOST2="/etc/SSHPlus/v2ray/lisportt.log"
    local RETURN="$(cat $HOST|cut -d'|' -f2)"
    local IDEUUID="$(cat $HOST|cut -d'|' -f1)"
    if [[ -z $RETURN ]]; then
    echo -e "----- NINGUN PUERTO REGISTRADO -----"
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    else
    i=1
    while read hostreturn ; do
    iptables -n -v -L > /etc/SSHPlus/v2ray/data1.log 
    statsss=$(cat /etc/SSHPlus/v2ray/data1.log|grep -w "tcp spt:$hostreturn quota:"|cut -d' ' -f3,4,5)
    gblim=$(cat /etc/SSHPlus/v2ray/lisportt.log|grep -w "$hostreturn"|cut -d'|' -f2)
    local contador_secuencial+="         \e[97mPUERTO: \e[93m$hostreturn \e[97m|\e[93m$statsss \e[97m|\e[93m $gblim GB  \n"          
          if [[ $i -gt 30 ]]; then
    	      echo -e "$contador_secuencial"
    	  unset contador_secuencial
    	  unset i
    	  fi
    let i++
    done <<< "$IDEUUID"
    [[ ! -z $contador_secuencial ]] && {
    linesss=$(cat /etc/SSHPlus/v2ray/lisportt.log | wc -l)
    	      echo -e "$contador_secuencial \n Puertos Limitados: $linesss"
    	}
    fi
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    }
    ###LIM
    liport () {
    while true; do
         echo -ne "\e[91m >> Puerto a limitar:\033[1;92m " && read portbg
         if [[ -z "$portbg" ]]; then
         echo -e "$msg17" && continue
         elif [[ "$portbg" != +([0-9]) ]]; then
         echo -e "$msg16" && continue
         elif [[ "$portbg" -gt "1000" ]]; then
         echo -e "$msg16" && continue
         fi 
         break
    done
    while true; do
         echo -ne "\e[91m >> Cantidad de GB:\033[1;92m " && read capgb
         if [[ -z "$capgb" ]]; then
         echo -e "$msg17" && continue
         elif [[ "$capgb" != +([0-9]) ]]; then
         echo -e "$msg15" && continue
         elif [[ "$capgb" -gt "1000" ]]; then
         echo -e "$msg15" && continue
         fi 
         break
    done
    uml1=1073741824
    gbuser="$capgb"
    let multiplicacion=$uml1*$gbuser
    sudo iptables -I OUTPUT -p tcp --sport $portbg -j DROP
    sudo iptables -I OUTPUT -p tcp --sport $portbg -m quota --quota $multiplicacion -j ACCEPT
    iptables-save > /etc/iptables/rules.v4
    echo ""
    echo -e " Puerto seleccionado: $portbg | Cantidad de GB: $gbuser"
    echo ""
    echo " $portbg | $gbuser | $multiplicacion " >> /etc/SSHPlus/v2ray/lisportt.log 
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    }
    ###RES
    resdata () {
    VPSsec=$(date +%s)
    local HOST="/etc/SSHPlus/v2ray/lisportt.log"
    local HOST2="/etc/SSHPlus/v2ray/lisportt.log"
    local RETURN="$(cat $HOST|cut -d'|' -f2)"
    local IDEUUID="$(cat $HOST|cut -d'|' -f1)"
    if [[ -z $RETURN ]]; then
    echo -e "----- NINGUN PUERTO REGISTRADO -----"
    return 0
    else
    i=1
    while read hostreturn ; do
    iptables -n -v -L > /etc/SSHPlus/v2ray/data1.log 
    statsss=$(cat /etc/SSHPlus/v2ray/data1.log|grep -w "tcp spt:$hostreturn quota:"|cut -d' ' -f3,4,5)
    gblim=$(cat /etc/SSHPlus/v2ray/lisportt.log|grep -w "$hostreturn"|cut -d'|' -f2)
    local contador_secuencial+="         \e[97mPUERTO: \e[93m$hostreturn \e[97m|\e[93m$statsss \e[97m|\e[93m $gblim GB  \n"  
            
          if [[ $i -gt 30 ]]; then
    	      echo -e "$contador_secuencial"
    	  unset contador_secuencial
    	  unset i
    	  fi
    let i++
    done <<< "$IDEUUID"

    [[ ! -z $contador_secuencial ]] && {
    linesss=$(cat /etc/SSHPlus/v2ray/lisportt.log | wc -l)
    	      echo -e "$contador_secuencial \n Puertos Limitados: $linesss"
    	}
    fi
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"

    while true; do
         echo -ne "\e[91m >> Puerto a limpiar:\033[1;92m " && read portbg
         if [[ -z "$portbg" ]]; then
         echo -e "$msg17" && continue
         elif [[ "$portbg" != +([0-9]) ]]; then
         echo -e "$msg16" && continue
         elif [[ "$portbg" -gt "1000" ]]; then
         echo -e "$msg16" && continue
         fi 
         break
    done
    invaliduuid () {
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\e[91m                PUERTO NO VALIDO \n"
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    }
    [[ $(sed -n '/'${portbg}'/=' /etc/SSHPlus/v2ray/lisportt.log|head -1) ]] || invaliduuid
    gblim=$(cat /etc/SSHPlus/v2ray/lisportt.log|grep -w "$portbg"|cut -d'|' -f3)
    sudo iptables -D OUTPUT -p tcp --sport $portbg -j DROP
    sudo iptables -D OUTPUT -p tcp --sport $portbg -m quota --quota $gblim -j ACCEPT
    iptables-save > /etc/iptables/rules.v4
    lineP=$(sed -n '/'${portbg}'/=' /etc/SSHPlus/v2ray/lisportt.log)
    sed -i "${linePre}d" /etc/SSHPlus/v2ray/lisportt.log
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    }
    ## MENU
    v2ray_opt "1" "LIMITAR DATOS x PUERTO"
    v2ray_opt "2" "RESTABLECER DATOS DE PUERTO"
    v2ray_opt "3" "VER DATOS CONSUMIDOS"
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    v2ray_opt "0" "VOLVER"
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    selection=$(selection_fun 3)
    case ${selection} in
    1)liport ;;
    2)resdata;;
    3)estarts;;
    0)

    ;;
    esac
    }

    #.
    limpiador_activador () {
    unset PIDGEN
    PIDGEN=$(ps aux|grep -v grep|grep "limv2ray")
    if [[ ! $PIDGEN ]]; then
    screen -dmS limv2ray watch -n 21600 limv2ray
    else
    #killall screen
    screen -S limv2ray -p 0 -X quit
    fi
    unset PID_GEN
    PID_GEN=$(ps x|grep -v grep|grep "limv2ray")
    [[ ! $PID_GEN ]] && PID_GEN="\e[91m [ DESACTIVADO ] " || PID_GEN="\e[92m [ ACTIVADO ] "
    statgen="$(echo $PID_GEN)"
    clear 
    clear
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    v2ray_title "ELIMINAR EXPIRADOS | UUID V2RAY"
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo ""
    echo -e "                    $statgen " 
    echo "" 						
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    }

    selection_fun () {
    local selection="null"
    local range
    for((i=0; i<=$1; i++)); do range[$i]="$i "; done
    while [[ ! $(echo ${range[*]}|grep -w "$selection") ]]; do
    echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} " >&2
    read selection
    tput cuu1 >&2 && tput dl1 >&2
    done
    echo $selection
    }

    PID_GEN=$(ps x|grep -v grep|grep "limv2ray")
    [[ ! $PID_GEN ]] && PID_GEN="\e[91m [ DESACTIVADO ] " || PID_GEN="\e[92m [ ACTIVADO ] "
    statgen="$(echo $PID_GEN)"
    #SPR & 
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"

    pausa_v2ray() {
    echo ""
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter
    }

    linea_v2ray() {
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    }

    editar_json_v2ray() {
    clear
    linea_v2ray
    v2ray_title "MODIFICAR JSON V2RAY"
    linea_v2ray
    local cfg
    cfg="$(v2ray_config_file)"
    [[ -z "$cfg" ]] && echo -e "\033[1;31mNo existe config.json de V2Ray/Xray\033[0m" && pausa_v2ray && ajustes_v2ray
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
    ajustes_v2ray
    }

    modificar_uuid_v2ray() {
    clear
    v2ray_title "MODIFICAR UUID V2RAY"
    local cfg tmp
    cfg="$(v2ray_config_file)"
    [[ -z "$cfg" ]] && echo -e "\033[1;31mNo existe config.json de V2Ray/Xray\033[0m" && pausa_v2ray && ajustes_v2ray
    v2ray_ensure_legacy_config "$cfg"
    cfg="/etc/v2ray/config.json"
    if ! v2ray_require_jq; then
    echo -e "\033[1;31mjq no esta instalado; no se puede modificar el JSON de forma segura.\033[0m"
    pausa_v2ray
    ajustes_v2ray
    fi
    [[ ! -s /etc/SSHPlus/RegV2ray ]] && echo -e "\033[1;31mNo hay usuarios V2RAY registrados.\033[0m" && pausa_v2ray && ajustes_v2ray
    echo -e "\033[1;37m        SELECIONAR USUARIOS (UUID) PARA MODIFICAR\033[0m"
    v2ray_line
    mapfile -t uuid_list < <(awk -F'|' '{gsub(/ /,"",$1); if($1!="") print $1}' /etc/SSHPlus/RegV2ray)
    for i in "${!uuid_list[@]}"; do
    v2ray_opt "$((i+1))" "${uuid_list[$i]}"
    done
    v2ray_opt "0" "CANCELAR"
    v2ray_line
    while true; do
    echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} "
    read uuid_sel
    [[ "$uuid_sel" = "0" ]] && ajustes_v2ray
    [[ "$uuid_sel" =~ ^[0-9]+$ ]] && [[ "$uuid_sel" -ge 1 ]] && [[ "$uuid_sel" -le "${#uuid_list[@]}" ]] && break
    echo -e "\033[1;31mOpcion no valida!\033[0m"
    sleep 1
    done
    uuid_actual="${uuid_list[$((uuid_sel-1))]}"
    grep -q "$uuid_actual" "$cfg" || { echo -e "\033[1;31mUUID no encontrado.\033[0m"; pausa_v2ray; ajustes_v2ray; }
    echo -ne "\e[91m >> Nuevo UUID (Enter para generar):\033[1;92m " && read uuid_nuevo
    [[ -z "$uuid_nuevo" ]] && uuid_nuevo="$(uuidgen)"
    if ! v2ray_valid_uuid "$uuid_nuevo"; then
    echo -e "\033[1;31mUUID no valido.\033[0m"
    pausa_v2ray
    ajustes_v2ray
    fi
    if grep -q "$uuid_nuevo" /etc/SSHPlus/RegV2ray 2>/dev/null || grep -q "$uuid_nuevo" "$cfg" 2>/dev/null; then
    echo -e "\033[1;31mYA HAY UN USUARIO CON ESTE UUID\033[0m"
    pausa_v2ray
    ajustes_v2ray
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
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg" || {
      rm -f "$tmp"
      echo -e "\033[1;31mNo se pudo modificar el UUID en config.json.\033[0m"
      pausa_v2ray
      ajustes_v2ray
    }
    grep -q "$uuid_nuevo" "$cfg" || {
      echo -e "\033[1;31mNo se pudo confirmar el nuevo UUID en config.json.\033[0m"
      pausa_v2ray
      ajustes_v2ray
    }
    [[ -e /etc/SSHPlus/RegV2ray ]] && sed -i "s;$uuid_actual;$uuid_nuevo;g" /etc/SSHPlus/RegV2ray
    v2ray_restart_service
    echo -e "\033[1;32mUUID modificado correctamente.\033[0m"
    echo -e "\033[1;33mNuevo UUID: \033[1;37m$uuid_nuevo\033[0m"
    pausa_v2ray
    ajustes_v2ray
    }

    modificar_path_v2ray() {
    clear
    linea_v2ray
    v2ray_title "MODIFICAR PATH V2RAY"
    linea_v2ray
    local cfg
    cfg="$(v2ray_config_file)"
    [[ -z "$cfg" ]] && echo -e "\033[1;31mNo existe config.json de V2Ray/Xray\033[0m" && pausa_v2ray && ajustes_v2ray
    v2ray_ensure_legacy_config "$cfg"
    cfg="/etc/v2ray/config.json"
    path_actual="$(grep -m1 '"path"' "$cfg" | awk -F '"' '{print $4}')"
    [[ -z "$path_actual" ]] && path_actual="/"
    echo -e "\033[1;33mPath actual detectado: \033[1;37m$path_actual\033[0m"
    echo -ne "\e[91m >> Nuevo path V2RAY:\033[1;92m " && read path_nuevo
    [[ -z "$path_nuevo" ]] && echo -e "$msg17" && pausa_v2ray && ajustes_v2ray
    [[ "$path_nuevo" != /* ]] && path_nuevo="/$path_nuevo"
    cp "$cfg" "$cfg.bak-$(date +%s)"
    if v2ray_require_jq; then
    jq --arg newpath "$path_nuevo" '(.inbounds[]?.streamSettings.wsSettings.path?) |= if . == null then . else $newpath end | (.inbounds[]?.streamSettings.xhttpSettings.path?) |= if . == null then . else $newpath end' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
    else
    sed -i "0,/\"path\"[[:space:]]*:/s;\"path\"[[:space:]]*:[[:space:]]*\"[^\"]*\";\"path\": \"$path_nuevo\";" "$cfg"
    fi
    v2ray_restart_service
    echo -e "\033[1;32mPath modificado correctamente.\033[0m"
    echo -e "\033[1;33mNuevo path: \033[1;37m$path_nuevo\033[0m"
    pausa_v2ray
    ajustes_v2ray
    }

    # ==================== GESTION XRAY XHTTP ====================
    xhttp_is_installed() {
    [[ -f /usr/local/bin/xray && -f /usr/local/etc/xray/config.json ]]
    }

    instalar_xray_xhttp() {
    local port path domain uuid user exp xray_url arch asset
    clear
    v2ray_title "INSTALAR XRAY XHTTP"
    echo -ne "${SSHPlus_DARK_GREEN}PUERTO XRAY XHTTP [Enter = 8443]:${SCOLOR} " && read port
    [[ -z "$port" ]] && port="8443"
    if ! v2ray_valid_port "$port"; then
    echo -e "\033[1;31mPuerto no valido. Use 1-65535.\033[0m"
    pausa_v2ray
    menu_xray_xhttp
    return
    fi
    if v2ray_port_in_use_by_other "$port" "/usr/local/etc/xray/config.json"; then
    v2ray_warn_port_busy "$port"
    pausa_v2ray
    menu_xray_xhttp
    return
    fi
    echo -ne "${SSHPlus_DARK_GREEN}PATH XHTTP [Enter = /xhttp]:${SCOLOR} " && read path
    [[ -z "$path" ]] && path="/xhttp"
    path="$(printf '%s' "$path" | tr -d '"\\[:space:]')"
    [[ "$path" != /* ]] && path="/$path"
    echo -ne "${SSHPlus_DARK_GREEN}DOMINIO/SNI [opcional]:${SCOLOR} " && read domain
    domain="$(printf '%s' "$domain" | tr -d '"\\[:space:]')"
    [[ -n "$domain" ]] && mkdir -p /etc/SSHPlus/v2ray && echo "$domain" > /etc/SSHPlus/v2ray/domain
    echo -ne "${SSHPlus_DARK_GREEN}USUARIO [Enter = xhttp]:${SCOLOR} " && read user
    user="$(printf '%s' "$user" | sed -e 's/[^a-zA-Z0-9_. -]//g')"
    [[ -z "$user" ]] && user="xhttp"
    uuid="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
    exp="$(date '+%Y-%m-%d' -d '+365 days' 2>/dev/null || date '+%Y-%m-%d')"

    mkdir -p /usr/local/etc/xray /etc/SSHPlus/v2ray /etc/SSHPlus
    arch="$(uname -m)"
    case "$arch" in
    x86_64|amd64) asset="Xray-linux-64.zip" ;;
    aarch64|arm64) asset="Xray-linux-arm64-v8a.zip" ;;
    *) echo -e "\033[1;31mArquitectura no soportada: $arch\033[0m"; pausa_v2ray; menu_xray_xhttp; return ;;
    esac
    xray_url="https://github.com/XTLS/Xray-core/releases/latest/download/${asset}"
    if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y unzip curl wget ca-certificates jq uuid-runtime >/dev/null 2>&1 || true
    fi
    for dep in unzip jq; do
    if ! command -v "$dep" >/dev/null 2>&1; then
    echo -e "\033[1;31mDependencia faltante: $dep\033[0m"
    pausa_v2ray
    menu_xray_xhttp
    return
    fi
    done
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo -e "\033[1;31mNecesita curl o wget para descargar Xray.\033[0m"
    pausa_v2ray
    menu_xray_xhttp
    return
    fi
    cd /tmp || { echo -e "\033[1;31mNo se pudo acceder a /tmp\033[0m"; pausa_v2ray; menu_xray_xhttp; return; }
    rm -rf xray-install xray.zip
    mkdir -p xray-install
    if command -v curl >/dev/null 2>&1; then
    curl -fL -o xray.zip "$xray_url"
    else
    wget -O xray.zip "$xray_url"
    fi
    [[ -s xray.zip ]] || { echo -e "\033[1;31mNo se pudo descargar Xray.\033[0m"; pausa_v2ray; menu_xray_xhttp; return; }
    unzip -o xray.zip -d xray-install >/dev/null 2>&1 || { echo -e "\033[1;31mNo se pudo descomprimir Xray.\033[0m"; pausa_v2ray; menu_xray_xhttp; return; }
    install -m 755 xray-install/xray /usr/local/bin/xray || { echo -e "\033[1;31mNo se pudo instalar /usr/local/bin/xray.\033[0m"; pausa_v2ray; menu_xray_xhttp; return; }

    cat >/usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-xhttp",
      "listen": "0.0.0.0",
      "port": ${port},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "path": "${path}",
          "mode": "packet-up"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF

    cat >/etc/systemd/system/xray.service <<EOF
[Unit]
Description=TunnelCore Xray XHTTP Service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray >/dev/null 2>&1
    if ! systemctl is-active xray >/dev/null 2>&1; then
    echo -e "\033[1;31mXray no pudo iniciar. Revise: systemctl status xray\033[0m"
    pausa_v2ray
    menu_xray_xhttp
    return
    fi
    [[ -f /etc/SSHPlus/RegV2ray ]] || touch /etc/SSHPlus/RegV2ray
    grep -q "$uuid" /etc/SSHPlus/RegV2ray 2>/dev/null || echo "  $uuid | $user | $exp " >> /etc/SSHPlus/RegV2ray
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;32m✓ XRAY XHTTP INSTALADO CORRECTAMENTE\033[0m"
    echo -e "${SSHPlus_DARK_GREEN}PUERTO:${SCOLOR} \033[1;37m$port\033[0m"
    echo -e "${SSHPlus_DARK_GREEN}PATH:${SCOLOR} \033[1;37m$path\033[0m"
    [[ -n "$domain" ]] && echo -e "${SSHPlus_DARK_GREEN}DOMINIO:${SCOLOR} \033[1;37m$domain\033[0m"
    echo -e "${SSHPlus_DARK_GREEN}UUID:${SCOLOR} \033[1;37m$uuid\033[0m"
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    pausa_v2ray
    menu_xray_xhttp
    }

    info_xray_xhttp() {
    clear
    v2ray_title "INFORMACION XRAY XHTTP"
    local cfg="/usr/local/etc/xray/config.json"
    if [[ ! -f "$cfg" ]]; then
    echo -e "\033[1;31mNo se encontro config.json de Xray.\033[0m"
    pausa_v2ray
    menu_xray_xhttp
    return
    fi
    local port path uuid ip host
    port="$(jq -r '.inbounds[0].port // "8443"' "$cfg" 2>/dev/null)"
    path="$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path // "/xhttp"' "$cfg" 2>/dev/null)"
    uuid="$(jq -r '.inbounds[0].settings.clients[0].id // ""' "$cfg" 2>/dev/null)"
    ip="$(cat /etc/SSHPlus/IP 2>/dev/null || v2ray_public_ip)"
    host="${ip}"
    [[ -s /etc/SSHPlus/Dominio ]] && host="$(cat /etc/SSHPlus/Dominio | head -1 | tr -d ' ')"

    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "${SSHPlus_DARK_GREEN}IP / HOST :${SCOLOR} \033[1;37m$host\033[0m"
    echo -e "${SSHPlus_DARK_GREEN}PUERTO    :${SCOLOR} \033[1;37m$port\033[0m"
    echo -e "${SSHPlus_DARK_GREEN}PROTOCOLO :${SCOLOR} \033[1;37mVLESS\033[0m"
    echo -e "${SSHPlus_DARK_GREEN}NETWORK   :${SCOLOR} \033[1;37mxhttp\033[0m"
    echo -e "${SSHPlus_DARK_GREEN}PATH      :${SCOLOR} \033[1;37m$path\033[0m"
    echo -e "${SSHPlus_DARK_GREEN}UUID      :${SCOLOR} \033[1;37m$uuid\033[0m"
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\033[1;33mLINK VLESS (Directo / Sin TLS):\033[0m"
    echo -e "\033[1;37mvless://${uuid}@${host}:${port}?encryption=none&security=none&type=xhttp&path=$(v2ray_urlencode_path "$path")&mode=packet-up#TunnelCore-XHTTP\033[0m"
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    pausa_v2ray
    menu_xray_xhttp
    }

    cambiar_puerto_xhttp() {
    clear
    v2ray_title "CAMBIAR PUERTO XRAY XHTTP"
    local cfg="/usr/local/etc/xray/config.json"
    local cur_port="$(jq -r '.inbounds[0].port // "8443"' "$cfg" 2>/dev/null)"
    echo -e "${SSHPlus_DARK_GREEN}PUERTO ACTUAL:${SCOLOR} \033[1;37m$cur_port\033[0m"
    echo -ne "${SSHPlus_DARK_GREEN}NUEVO PUERTO [1-65535]:${SCOLOR} " && read new_port
    [[ -z "$new_port" ]] && menu_xray_xhttp && return
    if ! v2ray_valid_port "$new_port"; then
    echo -e "\033[1;31mPuerto no valido.\033[0m"
    pausa_v2ray
    menu_xray_xhttp
    return
    fi
    if v2ray_port_in_use_by_other "$new_port" "$cfg"; then
    v2ray_warn_port_busy "$new_port"
    pausa_v2ray
    menu_xray_xhttp
    return
    fi
    local tmp="${cfg}.tmp"
    jq --argjson p "$new_port" '.inbounds[0].port = $p' "$cfg" > "$tmp" && mv "$tmp" "$cfg" || {
      rm -f "$tmp"
      echo -e "\033[1;31mError al actualizar config.json.\033[0m"
      pausa_v2ray
      menu_xray_xhttp
      return
    }
    systemctl restart xray >/dev/null 2>&1
    echo ""
    echo -e "\033[1;32m✓ Puerto cambiado a $new_port y servicio reiniciado.\033[0m"
    pausa_v2ray
    menu_xray_xhttp
    }

    cambiar_path_xhttp() {
    clear
    v2ray_title "CAMBIAR PATH XRAY XHTTP"
    local cfg="/usr/local/etc/xray/config.json"
    local cur_path="$(jq -r '.inbounds[0].streamSettings.xhttpSettings.path // "/xhttp"' "$cfg" 2>/dev/null)"
    echo -e "${SSHPlus_DARK_GREEN}PATH ACTUAL:${SCOLOR} \033[1;37m$cur_path\033[0m"
    echo -ne "${SSHPlus_DARK_GREEN}NUEVO PATH [ej: /mipath]:${SCOLOR} " && read new_path
    [[ -z "$new_path" ]] && menu_xray_xhttp && return
    [[ "$new_path" != /* ]] && new_path="/$new_path"
    local tmp="${cfg}.tmp"
    jq --arg p "$new_path" '.inbounds[0].streamSettings.xhttpSettings.path = $p' "$cfg" > "$tmp" && mv "$tmp" "$cfg" || {
      rm -f "$tmp"
      echo -e "\033[1;31mError al actualizar config.json.\033[0m"
      pausa_v2ray
      menu_xray_xhttp
      return
    }
    systemctl restart xray >/dev/null 2>&1
    echo ""
    echo -e "\033[1;32m✓ Path cambiado a $new_path y servicio reiniciado.\033[0m"
    pausa_v2ray
    menu_xray_xhttp
    }

    cambiar_uuid_xhttp() {
    clear
    v2ray_title "CAMBIAR UUID XRAY XHTTP"
    local cfg="/usr/local/etc/xray/config.json"
    local cur_uuid="$(jq -r '.inbounds[0].settings.clients[0].id // ""' "$cfg" 2>/dev/null)"
    echo -e "${SSHPlus_DARK_GREEN}UUID ACTUAL:${SCOLOR} \033[1;37m$cur_uuid\033[0m"
    echo -ne "${SSHPlus_DARK_GREEN}NUEVO UUID [Enter = generar automatico]:${SCOLOR} " && read new_uuid
    [[ -z "$new_uuid" ]] && new_uuid="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
    if ! v2ray_valid_uuid "$new_uuid"; then
    echo -e "\033[1;31mUUID no valido.\033[0m"
    pausa_v2ray
    menu_xray_xhttp
    return
    fi
    local tmp="${cfg}.tmp"
    jq --arg u "$new_uuid" '.inbounds[0].settings.clients[0].id = $u' "$cfg" > "$tmp" && mv "$tmp" "$cfg" || {
      rm -f "$tmp"
      echo -e "\033[1;31mError al actualizar config.json.\033[0m"
      pausa_v2ray
      menu_xray_xhttp
      return
    }
    [[ -f /etc/SSHPlus/RegV2ray ]] && sed -i "s/$cur_uuid/$new_uuid/g" /etc/SSHPlus/RegV2ray
    systemctl restart xray >/dev/null 2>&1
    echo ""
    echo -e "\033[1;32m✓ UUID actualizado a: $new_uuid\033[0m"
    pausa_v2ray
    menu_xray_xhttp
    }

    reiniciar_xray_xhttp() {
    clear
    v2ray_title "REINICIAR XRAY XHTTP"
    systemctl restart xray >/dev/null 2>&1
    if systemctl is-active xray >/dev/null 2>&1; then
      echo -e "\033[1;32m✓ Servicio Xray reiniciado correctamente.\033[0m"
    else
      echo -e "\033[1;31m✗ Error al iniciar servicio Xray. Revise: systemctl status xray\033[0m"
    fi
    pausa_v2ray
    menu_xray_xhttp
    }

    desinstalar_xray_xhttp() {
    clear
    v2ray_title "DESINSTALAR XRAY XHTTP"
    if ! xhttp_is_installed; then
    echo -e "\033[1;31mXray XHTTP no esta instalado.\033[0m"
    pausa_v2ray
    menu_xray_xhttp
    return
    fi
    echo -ne "${SSHPlus_DARK_GREEN}CONFIRMAR DESINSTALACION XRAY XHTTP [s/n]:${SCOLOR} " && read resp
    [[ ! "$resp" =~ ^[sS]$ ]] && menu_xray_xhttp && return
    systemctl stop xray >/dev/null 2>&1 || true
    systemctl disable xray >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/xray.service
    rm -f /usr/local/bin/xray /usr/bin/xray /bin/xray
    rm -rf /usr/local/etc/xray /etc/xray /var/log/xray
    systemctl daemon-reload >/dev/null 2>&1
    echo ""
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    echo -e "\e[92m       XRAY XHTTP DESINSTALADO CORRECTAMENTE "
    echo -e "${SSHPlus_CYAN}============================================================${SCOLOR}"
    pausa_v2ray

    }

    editar_json_xhttp() {
    clear
    v2ray_title "MODIFICAR JSON XRAY XHTTP"
    local cfg="/usr/local/etc/xray/config.json"
    if [[ ! -f "$cfg" ]]; then
    echo -e "\033[1;31mNo se encontro config.json de Xray XHTTP.\033[0m"
    pausa_v2ray
    menu_xray_xhttp
    return
    fi
    if command -v nano >/dev/null 2>&1; then
    nano "$cfg"
    elif command -v vi >/dev/null 2>&1; then
    vi "$cfg"
    else
    echo -e "\033[1;31mNo se encontro editor (nano/vi).\033[0m"
    echo -e "\033[1;37mEdite manualmente: $cfg\033[0m"
    pausa_v2ray
    menu_xray_xhttp
    return
    fi
    echo -ne "${SSHPlus_DARK_GREEN}Reiniciar Xray ahora? [s/n]:${SCOLOR} " && read resp
    if [[ "$resp" =~ ^[sS]$ ]]; then
    systemctl restart xray >/dev/null 2>&1
    echo -e "\033[1;32mXray XHTTP reiniciado.\033[0m"
    fi
    pausa_v2ray
    menu_xray_xhttp
    }

    v2ray_write_inbound_json() {
    local proto="$1" network="$2" tls="$3" port="$4" path="$5" uuid="$6" password="$7" method="$8" reality_dest="$9" reality_server="${10}" reality_private="${11}" reality_short="${12}" tmp_json
    tmp_json="$(mktemp)"
    if [[ "$proto" == "socks" ]]; then
    cat > "$tmp_json" <<EOF
{
  "tag": "socks-${port}",
  "listen": "0.0.0.0",
  "port": ${port},
  "protocol": "socks",
  "settings": {
    "auth": "noauth",
    "udp": true
  }
}
EOF
    elif [[ "$proto" == "vmess" ]]; then
    if [[ "$network" == "tcp" ]]; then
    cat > "$tmp_json" <<EOF
{
  "tag": "vmess-tcp-${port}",
  "listen": "0.0.0.0",
  "port": ${port},
  "protocol": "vmess",
  "settings": {
    "clients": [
      { "id": "${uuid}", "email": "${proto}-${port}", "level": 0 }
    ]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "${tls}"
  }
}
EOF
    else
    if [[ "$network" == "xhttp" ]]; then
    cat > "$tmp_json" <<EOF
{
  "tag": "vmess-xhttp-${port}",
  "listen": "0.0.0.0",
  "port": ${port},
  "protocol": "vmess",
  "settings": {
    "clients": [
      { "id": "${uuid}", "email": "${proto}-${port}", "level": 0 }
    ]
  },
  "streamSettings": {
    "network": "xhttp",
    "security": "${tls}",
    "xhttpSettings": { "path": "${path}", "mode": "packet-up" }
  }
}
EOF
    else
    cat > "$tmp_json" <<EOF
{
  "tag": "vmess-${network}-${port}",
  "listen": "0.0.0.0",
  "port": ${port},
  "protocol": "vmess",
  "settings": {
    "clients": [
      { "id": "${uuid}", "email": "${proto}-${port}", "level": 0 }
    ]
  },
  "streamSettings": {
    "network": "${network}",
    "security": "${tls}",
    "tlsSettings": {
      "certificates": [
        {
          "certificateFile": "/root/TunnelCore/certificados/local/local.crt",
          "keyFile": "/root/TunnelCore/certificados/local/local.key"
        }
      ]
    },
    "${network}Settings": {
      "headers": {
        "Host": "${reality_server}"
      },
      "path": "${path}"
    }
  }
}
EOF
    fi
    fi
    elif [[ "$proto" == "trojan" ]]; then
    if [[ "$network" == "tcp" ]]; then
    cat > "$tmp_json" <<EOF
{
  "tag": "trojan-tcp-${port}",
  "listen": "0.0.0.0",
  "port": ${port},
  "protocol": "trojan",
  "settings": {
    "clients": [
      { "password": "${password}" }
    ]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "none"
  }
}
EOF
    else
    if [[ "$network" == "xhttp" ]]; then
    cat > "$tmp_json" <<EOF
{
  "tag": "trojan-xhttp-${port}",
  "listen": "0.0.0.0",
  "port": ${port},
  "protocol": "trojan",
  "settings": {
    "clients": [
      { "password": "${password}" }
    ]
  },
  "streamSettings": {
    "network": "xhttp",
    "security": "${tls}",
    "xhttpSettings": { "path": "${path}", "mode": "packet-up" }
  }
}
EOF
    else
    cat > "$tmp_json" <<EOF
{
  "tag": "trojan-${network}-${port}",
  "listen": "0.0.0.0",
  "port": ${port},
  "protocol": "trojan",
  "settings": {
    "clients": [
      { "password": "${password}" }
    ]
  },
  "streamSettings": {
    "network": "${network}",
    "security": "${tls}",
    "${network}Settings": { "path": "${path}" }
  }
}
EOF
    fi
    fi
    elif [[ "$proto" == "shadowsocks" ]]; then
    cat > "$tmp_json" <<EOF
{
  "tag": "shadowsocks-${port}",
  "listen": "0.0.0.0",
  "port": ${port},
  "protocol": "shadowsocks",
  "settings": {
    "method": "${method}",
    "password": "${password}",
    "network": "tcp,udp"
  }
}
EOF
    elif [[ "$tls" == "reality" ]]; then
    cat > "$tmp_json" <<EOF
{
  "tag": "vless-reality-${port}",
  "listen": "0.0.0.0",
  "port": ${port},
  "protocol": "vless",
  "settings": {
    "clients": [
      { "id": "${uuid}", "flow": "xtls-rprx-vision" }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "show": false,
      "dest": "${reality_dest}",
      "serverNames": [ "${reality_server}" ],
      "privateKey": "${reality_private}",
      "shortIds": [ "${reality_short}" ]
    }
  }
}
EOF
    else
    if [[ "$network" == "tcp" ]]; then
    cat > "$tmp_json" <<EOF
{
  "tag": "vless-tcp-${port}",
  "listen": "0.0.0.0",
  "port": ${port},
  "protocol": "vless",
  "settings": {
    "clients": [
      { "id": "${uuid}" }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "tcp",
    "security": "${tls}"
  }
}
EOF
    elif [[ "$network" == "grpc" ]]; then
    cat > "$tmp_json" <<EOF
{
  "tag": "vless-grpc-${port}",
  "listen": "0.0.0.0",
  "port": ${port},
  "protocol": "vless",
  "settings": {
    "clients": [
      { "id": "${uuid}" }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "grpc",
    "security": "${tls}",
    "grpcSettings": { "serviceName": "${path}" }
  }
}
EOF
    elif [[ "$network" == "xhttp" ]]; then
    cat > "$tmp_json" <<EOF
{
  "tag": "vless-xhttp-${port}",
  "listen": "0.0.0.0",
  "port": ${port},
  "protocol": "vless",
  "settings": {
    "clients": [
      { "id": "${uuid}" }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "xhttp",
    "security": "${tls}",
    "xhttpSettings": { "path": "${path}", "mode": "packet-up" }
  }
}
EOF
    else
    cat > "$tmp_json" <<EOF
{
  "tag": "${proto}-${network}-${port}",
  "listen": "0.0.0.0",
  "port": ${port},
  "protocol": "vless",
  "settings": {
    "clients": [
      { "id": "${uuid}" }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "${network}",
    "security": "${tls}",
    "${network}Settings": { "path": "${path}" }
  }
}
EOF
    fi
    fi
    echo "$tmp_json"
    }

    crear_protocolo_v2ray() {
    v2ray_install_wizard
    return
    local opt proto network tls link_tls port ext_port path domain host_header sni uuid user exp cfg uri enc_path vmess_json vmess_b64 vmess_tls tmp inbound_json password method reality_dest reality_server reality_private reality_public reality_short backup_file test_log port_cfg cfg_name
    clear
    v2ray_title "CREAR PROTOCOLO V2RAY / XRAY"
    if ! xhttp_is_installed; then
    echo -e "\033[1;33mXray-core no esta instalado. Primero se abrira el instalador base.\033[0m"
    pausa_v2ray
    instalar_xray_xhttp
    return
    fi
    echo -e "\033[1;33mVMess\033[0m"
    v2ray_opt "1" "VMess + WebSocket"
    v2ray_opt "2" "VMess + WebSocket CDN TLS"
    v2ray_opt "3" "VMess + WebSocket alternativo"
    v2ray_opt "4" "VMess + TCP"
    echo ""
    echo -e "\033[1;33mVLESS\033[0m"
    v2ray_opt "5" "VLESS + WebSocket"
    v2ray_opt "6" "VLESS + WebSocket CDN TLS"
    v2ray_opt "7" "VLESS + WebSocket alternativo"
    v2ray_opt "8" "VLESS + TCP"
    v2ray_opt "9" "VLESS + XHTTP"
    v2ray_opt "10" "VLESS + gRPC"
    v2ray_opt "11" "VLESS + Reality"
    echo ""
    echo -e "\033[1;33mOTROS\033[0m"
    v2ray_opt "12" "Trojan + WebSocket CDN TLS"
    v2ray_opt "13" "Trojan + TCP"
    v2ray_opt "14" "Shadowsocks"
    v2ray_line
    v2ray_opt "0" "VOLVER"
    v2ray_line
    selection=$(selection_fun 14)
    [[ "$selection" = "0" ]] && fun_v2raymanager && return

    case "$selection" in
      1) proto="vmess"; network="ws"; tls="none"; link_tls="none"; port="80"; ext_port="80"; path="/v2ray" ;;
      2) proto="vmess"; network="ws"; tls="none"; link_tls="tls"; port="80"; ext_port="443"; path="/v2ray" ;;
      3) proto="vmess"; network="ws"; tls="none"; link_tls="none"; port="8080"; ext_port="8080"; path="/v2ray" ;;
      4) proto="vmess"; network="tcp"; tls="none"; link_tls="none"; port="10086"; ext_port="10086"; path="" ;;
      5) proto="vless"; network="ws"; tls="none"; link_tls="none"; port="80"; ext_port="80"; path="/v2ray" ;;
      6) proto="vless"; network="ws"; tls="none"; link_tls="tls"; port="80"; ext_port="443"; path="/v2ray" ;;
      7) proto="vless"; network="ws"; tls="none"; link_tls="none"; port="8080"; ext_port="8080"; path="/v2ray" ;;
      8) proto="vless"; network="tcp"; tls="none"; link_tls="none"; port="10085"; ext_port="10085"; path="" ;;
      9) proto="vless"; network="xhttp"; tls="none"; link_tls="none"; port="8443"; ext_port="8443"; path="/xhttp" ;;
      10) proto="vless"; network="grpc"; tls="none"; link_tls="tls"; port="80"; ext_port="443"; path="grpc" ;;
      11) proto="vless"; network="tcp"; tls="reality"; link_tls="reality"; port="443"; ext_port="443"; path="" ;;
      12) proto="trojan"; network="ws"; tls="none"; link_tls="tls"; port="80"; ext_port="443"; path="/trojan" ;;
      13) proto="trojan"; network="tcp"; tls="none"; link_tls="none"; port="443"; ext_port="443"; path="" ;;
      14) proto="shadowsocks"; network="tcp"; tls="none"; link_tls="none"; port="8388"; ext_port="8388"; path="" ;;
    esac

    echo -ne "${SSHPlus_DARK_GREEN}NOMBRE CONFIG [Enter = conf${port}]:${SCOLOR} " && read cfg_name
    cfg_name="$(printf '%s' "$cfg_name" | sed -e 's/[^a-zA-Z0-9_.-]//g')"
    [[ -z "$cfg_name" ]] && cfg_name="conf${port}"
    user="$cfg_name"
    echo -ne "${SSHPlus_DARK_GREEN}PUERTO [Enter = $port]:${SCOLOR} " && read custom_port
    [[ -n "$custom_port" ]] && port="$custom_port"
    [[ "$link_tls" == "none" ]] && ext_port="$port"
    if ! v2ray_valid_port "$port"; then
    echo -e "\033[1;31mPuerto no valido. Use 1-65535.\033[0m"
    pausa_v2ray
    fun_v2raymanager
    return
    fi
    if v2ray_port_in_use_by_other "$port" "/usr/local/etc/xray/config.json"; then
    v2ray_warn_port_busy "$port"
    pausa_v2ray
    fun_v2raymanager
    return
    fi
    if [[ "$network" == "ws" || "$network" == "xhttp" ]]; then
    echo -ne "${SSHPlus_DARK_GREEN}PATH [Enter = $path]:${SCOLOR} " && read custom_path
    [[ -n "$custom_path" ]] && path="$custom_path"
    path="$(printf '%s' "$path" | tr -d '"\\[:space:]')"
    [[ "$path" != /* ]] && path="/$path"
    elif [[ "$network" == "grpc" ]]; then
    echo -ne "${SSHPlus_DARK_GREEN}SERVICE NAME gRPC [Enter = $path]:${SCOLOR} " && read custom_path
    [[ -n "$custom_path" ]] && path="$custom_path"
    path="$(printf '%s' "$path" | tr -d '"\\[:space:]')"
    fi

    domain="$(cat /etc/SSHPlus/v2ray/domain 2>/dev/null || cat /etc/SSHPlus/Dominio 2>/dev/null || echo "")"
    if [[ "$link_tls" == "tls" ]]; then
    echo -ne "${SSHPlus_DARK_GREEN}DOMINIO/SNI [${domain:-obligatorio}]:${SCOLOR} " && read input_domain
    [[ -n "$input_domain" ]] && domain="$input_domain"
    domain="$(printf '%s' "$domain" | tr -d '"\\[:space:]')"
    if [[ -z "$domain" ]]; then
    echo -e "\033[1;31mPara TLS necesita dominio/SNI.\033[0m"
    pausa_v2ray
    fun_v2raymanager
    return
    fi
    mkdir -p /etc/SSHPlus/v2ray
    echo "$domain" > /etc/SSHPlus/v2ray/domain
    host_header="$domain"
    sni="$domain"
    else
    domain="$(cat /etc/SSHPlus/IP 2>/dev/null || cat /etc/IP 2>/dev/null || v2ray_public_ip)"
    host_header=""
    sni=""
    fi

    uuid="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)"
    password="$(tc_rand_string 16 2>/dev/null || tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"
    method="aes-128-gcm"
    if [[ "$proto" == "shadowsocks" ]]; then
    echo -ne "${SSHPlus_DARK_GREEN}METODO [Enter = $method]:${SCOLOR} " && read input_method
    [[ -n "$input_method" ]] && method="$input_method"
    method="$(printf '%s' "$method" | tr -d '"\\[:space:]')"
    fi
    if [[ "$link_tls" == "reality" ]]; then
    reality_server="www.cloudflare.com"
    reality_dest="${reality_server}:443"
    reality_short="$(openssl rand -hex 4 2>/dev/null || date +%s | sha256sum | cut -c1-8)"
    echo -ne "${SSHPlus_DARK_GREEN}SNI REALITY [Enter = $reality_server]:${SCOLOR} " && read input_reality_server
    [[ -n "$input_reality_server" ]] && reality_server="$input_reality_server"
    reality_server="$(printf '%s' "$reality_server" | tr -d '"\\[:space:]')"
    reality_dest="${reality_server}:443"
    if /usr/local/bin/xray x25519 >/tmp/tc-xray-keys 2>/dev/null; then
    reality_private="$(awk '/Private key:/ {print $3}' /tmp/tc-xray-keys)"
    reality_public="$(awk '/Public key:/ {print $3}' /tmp/tc-xray-keys)"
    rm -f /tmp/tc-xray-keys
    fi
    if [[ -z "$reality_private" || -z "$reality_public" ]]; then
    echo -e "\033[1;31mNo se pudieron generar claves Reality con xray x25519.\033[0m"
    pausa_v2ray
    fun_v2raymanager
    return
    fi
    domain="$reality_server"
    fi
    exp="$(date '+%Y-%m-%d' -d '+365 days' 2>/dev/null || date '+%Y-%m-%d')"
    cfg="/usr/local/etc/xray/config.json"
    mkdir -p /usr/local/etc/xray /etc/SSHPlus/v2ray /etc/v2ray /etc/SSHPlus
    backup_file="${cfg}.bak-$(date +%s)"
    [[ -f "$cfg" ]] && cp "$cfg" "$backup_file"

    if [[ ! -s "$cfg" ]]; then
    cat > "$cfg" <<'EOF'
{
  "log": { "loglevel": "warning" },
  "inbounds": [],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" }
  ]
}
EOF
    fi

    inbound_json="$(v2ray_write_inbound_json "$proto" "$network" "$tls" "$port" "$path" "$uuid" "$password" "$method" "$reality_dest" "$reality_server" "$reality_private" "$reality_short")"
    tmp="${cfg}.tmp"
    if ! v2ray_require_jq; then
    echo -e "\033[1;31mjq no esta instalado; no se puede modificar config.json.\033[0m"
    rm -f "$inbound_json"
    pausa_v2ray
    fun_v2raymanager
    return
    fi
    jq --argjson port "$port" --arg proto "$proto" --arg network "$network" --arg tls "$tls" --arg path "$path" --arg uuid "$uuid" --slurpfile inbound "$inbound_json" '
      .log = (.log // { "loglevel": "warning" }) |
      .outbounds = ((.outbounds // []) | if length == 0 then [{ "protocol": "freedom", "tag": "direct" }] else . end) |
      .inbounds = (
        (.inbounds // []) as $inbounds |
        if ($proto == "shadowsocks" or $tls == "reality") then
          ($inbounds | map(select(.port != $port)) + [$inbound[0]])
        elif ($inbounds | any(.port == $port and .protocol == $proto and (.streamSettings.network // "tcp") == $network and ((.streamSettings.wsSettings.path // .streamSettings.xhttpSettings.path // .streamSettings.grpcSettings.serviceName // "") == $path))) then
          $inbounds | map(
            if (.port == $port and .protocol == $proto and (.streamSettings.network // "tcp") == $network and ((.streamSettings.wsSettings.path // .streamSettings.xhttpSettings.path // .streamSettings.grpcSettings.serviceName // "") == $path)) then
              if ((.settings.clients // []) | any(.id == $uuid or .password == $inbound[0].settings.clients[0].password)) then
                .
              else
                .settings.clients += [($inbound[0].settings.clients[0])]
              end
            else
              .
            end
          )
        else
          ($inbounds | map(select(.port != $port)) + [$inbound[0]])
        end
      )
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg" || {
    rm -f "$tmp" "$inbound_json"
    echo -e "\033[1;31mNo se pudo agregar el inbound al config.json.\033[0m"
    pausa_v2ray
    fun_v2raymanager
    return
    }
    port_cfg="/usr/local/etc/xray/config-${port}.json"
    jq -n --slurpfile inbound "$inbound_json" '
      {
        "log": { "loglevel": "warning", "access": "/var/log/xray/access-\($inbound[0].port).log", "error": "/var/log/xray/error-\($inbound[0].port).log" },
        "inbounds": [ $inbound[0] ],
        "outbounds": [
          { "protocol": "freedom", "tag": "direct" }
        ]
      }
    ' > "$port_cfg" || {
    rm -f "$tmp" "$inbound_json"
    echo -e "\033[1;31mNo se pudo crear config-${port}.json.\033[0m"
    pausa_v2ray
    fun_v2raymanager
    return
    }
    rm -f "$inbound_json"

    ln -sf "$cfg" /etc/v2ray/config.json 2>/dev/null || true
    test_log="/tmp/tunnelcore-xray-test.log"
    if /usr/local/bin/xray run -test -config "$port_cfg" >"$test_log" 2>&1; then
    v2ray_ensure_template_service
    systemctl disable --now xray >/dev/null 2>&1 || true
    systemctl restart "xray@${port}" >/dev/null 2>&1
    systemctl enable "xray@${port}" >/dev/null 2>&1
    else
    echo -e "\033[1;31mEl config.json generado no paso la validacion de Xray.\033[0m"
    [[ -s "$backup_file" ]] && cp "$backup_file" "$cfg"
    rm -f "$port_cfg"
    echo -e "\033[1;33mDetalle del error:\033[0m"
    sed -n '1,12p' "$test_log" 2>/dev/null
    pausa_v2ray
    fun_v2raymanager
    return
    fi
    mkdir -p /etc/SSHPlus/v2ray
    grep -v "^${port}|" /etc/SSHPlus/v2ray/configs.db 2>/dev/null > /etc/SSHPlus/v2ray/configs.db.tmp || true
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$port" "$cfg_name" "$proto" "$network" "$link_tls" "$domain" "$path" "$ext_port" "$sni" "xray" >> /etc/SSHPlus/v2ray/configs.db.tmp
    mv -f /etc/SSHPlus/v2ray/configs.db.tmp /etc/SSHPlus/v2ray/configs.db
    grep -q "$uuid" /etc/SSHPlus/RegV2ray 2>/dev/null || echo "  $uuid | $user | $exp " >> /etc/SSHPlus/RegV2ray

    if [[ "$type" == "xray" && "$network" == "xhttp" && "$link_tls" == "tls" ]]; then
    domain="local"
    sni="local"
    host_header="You-HostName.com"
    fi

    enc_path="$(v2ray_urlencode_path "$path")"
    if [[ "$proto" == "vmess" ]]; then
    vmess_tls=""
    [[ "$link_tls" == "tls" ]] && vmess_tls="tls"
    local vmess_alpn="" vmess_fp="" vmess_mode=""
    if [[ "$link_tls" == "tls" ]]; then
    vmess_fp="chrome"
    [[ "$network" == "xhttp" ]] && vmess_alpn="h2"
    fi
    [[ "$network" == "xhttp" ]] && vmess_mode="packet-up"
    vmess_json=$(cat <<EOF
{"v":"2","ps":"${user}","add":"${domain}","port":"${ext_port}","id":"${uuid}","aid":"0","scy":"auto","net":"${network}","type":"","host":"${host_header}","path":"${path}","tls":"${vmess_tls}","sni":"${sni}","alpn":"${vmess_alpn}","fp":"${vmess_fp}","mode":"${vmess_mode}"}
EOF
)
    vmess_b64="$(printf '%s' "$vmess_json" | base64 -w 0 2>/dev/null || printf '%s' "$vmess_json" | base64 | tr -d '\n')"
    uri="vmess://${vmess_b64}"
    elif [[ "$proto" == "trojan" ]]; then
    if [[ "$link_tls" == "tls" ]]; then
    if [[ "$network" == "xhttp" ]]; then
    uri="trojan://${password}@${domain}:${ext_port}?type=xhttp&security=tls&sni=${sni}&host=${host_header}&path=${enc_path}&mode=packet-up#${user}"
    else
    uri="trojan://${password}@${domain}:${ext_port}?type=${network}&security=tls&sni=${sni}&host=${host_header}&path=${enc_path}#${user}"
    fi
    elif [[ "$network" == "xhttp" ]]; then
    uri="trojan://${password}@${domain}:${ext_port}?type=xhttp&security=none&path=${enc_path}&mode=packet-up#${user}"
    elif [[ "$network" == "ws" ]]; then
    uri="trojan://${password}@${domain}:${ext_port}?type=ws&security=none&path=${enc_path}#${user}"
    else
    uri="trojan://${password}@${domain}:${ext_port}?security=none#${user}"
    fi
    elif [[ "$proto" == "shadowsocks" ]]; then
    local ss_userinfo
    ss_userinfo="$(printf '%s' "${method}:${password}" | base64 -w 0 2>/dev/null || printf '%s' "${method}:${password}" | base64 | tr -d '\n')"
    uri="ss://${ss_userinfo}@${domain}:${ext_port}#${user}"
    elif [[ "$link_tls" == "reality" ]]; then
    uri="vless://${uuid}@${domain}:${ext_port}?type=tcp&security=reality&sni=${reality_server}&pbk=${reality_public}&sid=${reality_short}&fp=chrome&flow=xtls-rprx-vision#${user}"
    elif [[ "$link_tls" == "tls" ]]; then
    if [[ "$network" == "grpc" ]]; then
    uri="vless://${uuid}@${domain}:${ext_port}?type=grpc&security=tls&sni=${sni}&serviceName=${path}#${user}"
    else
    if [[ "$network" == "xhttp" ]]; then
    uri="vless://${uuid}@${domain}:${ext_port}?encryption=none&type=xhttp&security=tls&sni=${sni}&host=${host_header}&path=${enc_path}&mode=packet-up#${user}"
    else
    uri="vless://${uuid}@${domain}:${ext_port}?type=${network}&security=tls&sni=${sni}&host=${host_header}&path=${enc_path}#${user}"
    fi
    fi
    else
    if [[ "$network" == "tcp" ]]; then
    uri="vless://${uuid}@${domain}:${ext_port}?type=tcp&security=none#${user}"
    elif [[ "$network" == "grpc" ]]; then
    uri="vless://${uuid}@${domain}:${ext_port}?type=grpc&security=none&serviceName=${path}#${user}"
    else
    if [[ "$network" == "xhttp" ]]; then
    uri="vless://${uuid}@${domain}:${ext_port}?encryption=none&type=xhttp&security=none&path=${enc_path}&mode=packet-up#${user}"
    else
    uri="vless://${uuid}@${domain}:${ext_port}?type=${network}&security=none&path=${enc_path}#${user}"
    fi
    fi
    fi

    clear
    v2ray_title "PROTOCOLO CREADO"
    printf "\033[1;32m%-18s\033[0m \033[1;37m%s\033[0m\n" "PROTOCOLO:" "$proto"
    printf "\033[1;32m%-18s\033[0m \033[1;37m%s\033[0m\n" "NETWORK:" "$network"
    printf "\033[1;32m%-18s\033[0m \033[1;37m%s\033[0m\n" "PUERTO:" "$port"
    printf "\033[1;32m%-18s\033[0m \033[1;37m%s\033[0m\n" "PUERTO LINK:" "$ext_port"
    printf "\033[1;32m%-18s\033[0m \033[1;37m%s\033[0m\n" "TLS LINK:" "$link_tls"
    printf "\033[1;32m%-18s\033[0m \033[1;37m%s\033[0m\n" "HOST:" "$domain"
    printf "\033[1;32m%-18s\033[0m \033[1;37m%s\033[0m\n" "PATH:" "$path"
    printf "\033[1;32m%-18s\033[0m \033[1;37m%s\033[0m\n" "UUID:" "$uuid"
    [[ "$proto" == "trojan" || "$proto" == "shadowsocks" ]] && printf "\033[1;32m%-18s\033[0m \033[1;37m%s\033[0m\n" "PASSWORD:" "$password"
    [[ "$proto" == "shadowsocks" ]] && printf "\033[1;32m%-18s\033[0m \033[1;37m%s\033[0m\n" "METODO:" "$method"
    [[ "$link_tls" == "reality" ]] && printf "\033[1;32m%-18s\033[0m \033[1;37m%s\033[0m\n" "PUBLIC KEY:" "$reality_public"
    v2ray_line
    echo -e "\033[1;33mLINK PARA IMPORTAR:\033[0m"
    echo -e "\033[1;36m${uri}\033[0m"
    v2ray_line
    pausa_v2ray
    fun_v2raymanager
    }

    v2ray_select_config() {
    local idx=1 line port name proto network tls domain path ext_port sni core_type choice
    V2SEL_PORT=""
    V2SEL_NAME=""
    V2SEL_PROTO=""
    V2SEL_NETWORK=""
    V2SEL_TLS=""
    V2SEL_DOMAIN=""
    V2SEL_PATH=""
    V2SEL_EXT_PORT=""
    V2SEL_SNI=""
    V2SEL_CORE="v2ray"
    [[ ! -s /etc/SSHPlus/v2ray/configs.db ]] && return 1
    v2ray_title "SELECTOR DE CONFIGURACION"
    while IFS='|' read -r port name proto network tls domain path ext_port sni core_type; do
    [[ -z "$port" ]] && continue
    [[ -z "$core_type" ]] && core_type="v2ray"
    printf "\033[1;32m[%s]\033[0m > \033[1;37m%s %s %s %s %s\033[0m\n" "$idx" "$name" "$proto" "$network" "$tls" "$port"
    eval "V2CFG_${idx}_PORT=\"\$port\""
    eval "V2CFG_${idx}_NAME=\"\$name\""
    eval "V2CFG_${idx}_PROTO=\"\$proto\""
    eval "V2CFG_${idx}_NETWORK=\"\$network\""
    eval "V2CFG_${idx}_TLS=\"\$tls\""
    eval "V2CFG_${idx}_DOMAIN=\"\$domain\""
    eval "V2CFG_${idx}_PATH=\"\$path\""
    eval "V2CFG_${idx}_EXT_PORT=\"\$ext_port\""
    eval "V2CFG_${idx}_SNI=\"\$sni\""
    eval "V2CFG_${idx}_CORE=\"\$core_type\""
    idx=$((idx + 1))
    done < /etc/SSHPlus/v2ray/configs.db
    v2ray_line
    v2ray_opt "0" "VOLVER"
    v2ray_line
    echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} "
    read choice
    [[ "$choice" = "0" ]] && return 1
    [[ ! "$choice" =~ ^[0-9]+$ || "$choice" -ge "$idx" || "$choice" -lt 1 ]] && return 1
    eval "V2SEL_PORT=\"\$V2CFG_${choice}_PORT\""
    eval "V2SEL_NAME=\"\$V2CFG_${choice}_NAME\""
    eval "V2SEL_PROTO=\"\$V2CFG_${choice}_PROTO\""
    eval "V2SEL_NETWORK=\"\$V2CFG_${choice}_NETWORK\""
    eval "V2SEL_TLS=\"\$V2CFG_${choice}_TLS\""
    eval "V2SEL_DOMAIN=\"\$V2CFG_${choice}_DOMAIN\""
    eval "V2SEL_PATH=\"\$V2CFG_${choice}_PATH\""
    eval "V2SEL_EXT_PORT=\"\$V2CFG_${choice}_EXT_PORT\""
    eval "V2SEL_SNI=\"\$V2CFG_${choice}_SNI\""
    eval "V2SEL_CORE=\"\$V2CFG_${choice}_CORE\""
    return 0
    }

    v2ray_show_port_json() {
    local cfg_file
    clear
    v2ray_select_config || return
    clear
    v2ray_title "conf: config.${V2SEL_PORT}.json"
    cfg_file="$(v2ray_config_path_for_port "$V2SEL_PORT")"
    if [[ -s "$cfg_file" ]]; then
    jq . "$cfg_file" 2>/dev/null || cat "$cfg_file"
    else
    echo -e "\033[1;31mNo existe configuracion para el puerto ${V2SEL_PORT}\033[0m"
    fi
    v2ray_line
    pausa_v2ray
    return
    }

    v2ray_edit_port_json() {
    local cfg_file
    clear
    v2ray_select_config || return
    cfg_file="$(v2ray_config_path_for_port "$V2SEL_PORT")"
    ${EDITOR:-nano} "$cfg_file"
    if [[ "$V2SEL_CORE" == "xray" ]]; then
    /usr/local/bin/xray run -test -config "$cfg_file" >/tmp/tunnelcore-xray-test.log 2>&1
    else
    /root/TunnelCore/v2ray/bin/v2ray/v2ray test -config "$cfg_file" >/tmp/tunnelcore-xray-test.log 2>&1
    fi
    if [[ "$?" = "0" ]]; then
    systemctl restart "$(v2ray_selected_unit "$V2SEL_PORT" "$V2SEL_CORE")" >/dev/null 2>&1
    echo -e "\033[1;32mConfiguracion validada y servicio reiniciado.\033[0m"
    else
    echo -e "\033[1;31mLa configuracion no paso la validacion de Xray.\033[0m"
    sed -n '1,12p' /tmp/tunnelcore-xray-test.log 2>/dev/null
    fi
    pausa_v2ray
    return
    }

    v2ray_delete_protocol() {
    clear
    v2ray_select_config || return
    echo -ne "\033[1;31mEliminar ${V2SEL_NAME} puerto ${V2SEL_PORT}? [S/N]: \033[0m"
    read ok
    [[ ! "$ok" =~ ^[sS]$ ]] && return
    systemctl disable --now "v2ray@${V2SEL_PORT}" "xray@${V2SEL_PORT}" >/dev/null 2>&1 || true
    rm -f "/root/TunnelCore/v2ray/conf/config.${V2SEL_PORT}.json"
    rm -f "/usr/local/etc/xray/config-${V2SEL_PORT}.json"
    rm -f "/usr/local/etc/xray/config.${V2SEL_PORT}.json"
    grep -v "^${V2SEL_PORT}|" /etc/SSHPlus/v2ray/configs.db > /etc/SSHPlus/v2ray/configs.db.tmp 2>/dev/null || true
    mv -f /etc/SSHPlus/v2ray/configs.db.tmp /etc/SSHPlus/v2ray/configs.db
    echo -e "\033[1;32mProtocolo eliminado.\033[0m"
    pausa_v2ray
    return
    }

    v2ray_services_status() {
    local port owner core unit
    clear
    v2ray_title "ESTADO DEL SERVICIO"
    if [[ -z "$(v2ray_ports_configured)" ]]; then
    echo -e "\033[1;31mNo se detectaron servicios/configuraciones V2Ray por puerto.\033[0m"
    echo -e "\033[1;37mRevise si existen archivos config-PORT.json o servicios v2ray@PORT.\033[0m"
    v2ray_line
    pausa_v2ray
    return
    return
    fi
    for port in $(v2ray_ports_configured); do
    core="$(v2ray_core_for_port "$port")"
    unit="$(v2ray_selected_unit "$port" "$core")"
    v2ray_line
    echo -e "\033[1;33mEstado del servicio ${unit}\033[0m"
    v2ray_line
    systemctl status "$unit" --no-pager 2>/dev/null || true
    if systemctl is-active "$unit" >/dev/null 2>&1; then
    printf "\033[1;32m%s ACTIVO\033[0m\n" "$unit"
    else
    printf "\033[1;31m%s DETENIDO\033[0m\n" "$unit"
    fi
    owner="$(v2ray_port_owner "$port")"
    [[ -n "$owner" ]] && printf "\033[1;33mPuerto %s:\033[0m \033[1;37m%s\033[0m\n" "$port" "$owner"
    journalctl -u "$unit" -n 3 --no-pager 2>/dev/null | sed 's/^/  /'
    journalctl -u "$unit" -n 20 --no-pager 2>/dev/null | grep -q 'TLS handshake error.*EOF' && echo -e "\033[1;33mAviso: llega trafico al puerto, pero el cliente corta durante TLS. Revise SNI/Host o active Allow Insecure en la app.\033[0m"
    done
    v2ray_line
    pausa_v2ray
    return
    }

    v2ray_restart_all_services() {
    local port failed=0 core unit
    clear
    v2ray_title "REINICIAR SERVICIO"
    v2ray_ensure_template_service
    for port in $(v2ray_ports_configured); do
    core="$(v2ray_core_for_port "$port")"
    unit="$(v2ray_selected_unit "$port" "$core")"
    if systemctl restart "$unit" >/dev/null 2>&1; then
    systemctl enable "$unit" >/dev/null 2>&1
    printf "\033[1;32m%s reiniciado OK\033[0m\n" "$unit"
    else
    printf "\033[1;31m%s fallo al reiniciar\033[0m\n" "$unit"
    failed=1
    fi
    done
    [[ "$failed" = "0" ]] && echo -e "\033[1;32mServicios procesados.\033[0m"
    pausa_v2ray
    return
    }

    v2ray_toggle_all_services() {
    local port any_on=0 action core unit
    clear
    for port in $(v2ray_ports_configured); do
    core="$(v2ray_core_for_port "$port")"
    unit="$(v2ray_selected_unit "$port" "$core")"
    systemctl is-active "$unit" >/dev/null 2>&1 && any_on=1
    done
    if [[ "$any_on" = "1" ]]; then
    action="stop"
    else
    action="start"
    v2ray_ensure_template_service
    fi
    v2ray_title "INICIAR/PARAR SERVICIOS"
    for port in $(v2ray_ports_configured); do
    core="$(v2ray_core_for_port "$port")"
    unit="$(v2ray_selected_unit "$port" "$core")"
    systemctl "$action" "$unit" >/dev/null 2>&1
    printf "\033[1;37m%s -> %s\033[0m\n" "$unit" "$action"
    done
    pausa_v2ray
    return
    }

    v2ray_show_logs() {
    local mode="$1" port
    clear
    v2ray_select_config || return
    clear
    v2ray_title "LOG XRAY ${V2SEL_PORT}"
    case "$mode" in
      live) journalctl -u "$(v2ray_selected_unit "$V2SEL_PORT" "$V2SEL_CORE")" -f ;;
      all) journalctl -u "$(v2ray_selected_unit "$V2SEL_PORT" "$V2SEL_CORE")" --no-pager ;;
      *) journalctl -u "$(v2ray_selected_unit "$V2SEL_PORT" "$V2SEL_CORE")" -n 80 --no-pager ;;
    esac
    pausa_v2ray
    return
    }

    v2ray_add_user_port_config() {
    local cfg nick uuid days valid exp tmp proto network link_tls domain path ext_port add_host host_header sni allow_insecure enc_path uri vmess_json vmess_b64
    clear
    v2ray_select_config || return
    cfg="$(v2ray_config_path_for_port "$V2SEL_PORT")"
    if [[ ! -s "$cfg" ]]; then
    echo -e "\033[1;31mNo existe la configuracion del puerto ${V2SEL_PORT}.\033[0m"
    pausa_v2ray
    return
    fi
    proto="$(jq -r '.inbounds[0].protocol // ""' "$cfg" 2>/dev/null)"
    network="$(jq -r '.inbounds[0].streamSettings.network // "tcp"' "$cfg" 2>/dev/null)"
    if [[ "$proto" != "vmess" && "$proto" != "vless" ]]; then
    echo -e "\033[1;31mNuevo usuario automatico solo esta disponible para VMess/VLESS.\033[0m"
    echo -e "\033[1;37mPara Trojan/Shadowsocks cree otro protocolo o edite el JSON manualmente.\033[0m"
    pausa_v2ray
    return
    fi
    if ! jq -e '.inbounds[0].settings.clients | type == "array"' "$cfg" >/dev/null 2>&1; then
    echo -e "\033[1;31mEsta configuracion no tiene lista clients editable.\033[0m"
    pausa_v2ray
    return
    fi
    clear
    v2ray_title "Nuevo Usuario v2ray ${proto} ${V2SEL_TLS}"
    printf "\033[1;33mSERVICIO:\033[0m \033[1;37mv2ray\033[0m\n"
    printf "\033[1;33mPROTOCOLO:\033[0m \033[1;37m%s\033[0m\n" "$proto"
    echo -ne "${SSHPlus_DARK_GREEN}NOMBRE:${SCOLOR} "
    read nick
    nick="$(printf '%s' "$nick" | sed -e 's/[^a-zA-Z0-9_.-]//g')"
    [[ -z "$nick" ]] && nick="user"
    uuid="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null)"
    echo -ne "${SSHPlus_DARK_GREEN}UUID [$uuid]:${SCOLOR} "
    read input_uuid
    [[ -n "$input_uuid" ]] && uuid="$input_uuid"
    if ! v2ray_valid_uuid "$uuid"; then
    echo -e "\033[1;31mUUID no valido.\033[0m"
    pausa_v2ray
    return
    fi
    echo -ne "${SSHPlus_DARK_GREEN}EXPIRA EN:${SCOLOR} "
    read days
    [[ -z "$days" ]] && days="30"
    if [[ ! "$days" =~ ^[0-9]+$ ]]; then
    echo -e "\033[1;31mDias no validos.\033[0m"
    pausa_v2ray
    return
    fi
    valid="$(date '+%Y-%m-%d' -d "+${days} days" 2>/dev/null || date '+%Y-%m-%d')"
    exp="$(date '+%F' -d "+${days} days" 2>/dev/null || date '+%F')"
    tmp="${cfg}.tmp"
    cp "$cfg" "$cfg.bak-$(date +%s)" 2>/dev/null || true
    jq --arg uuid "$uuid" --arg email "$nick" --arg proto "$proto" '
      .inbounds[0].settings.clients += [(
        if $proto == "vless" then
          {"id": $uuid, "email": $email}
        else
          {"id": $uuid, "email": $email, "level": 0}
        end
      )]
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg" || {
    rm -f "$tmp"
    echo -e "\033[1;31mNo se pudo agregar el usuario al JSON.\033[0m"
    pausa_v2ray
    return
    }
    if [[ "$V2SEL_CORE" == "xray" ]]; then
    /usr/local/bin/xray run -test -config "$cfg" >/tmp/tunnelcore-xray-test.log 2>&1
    else
    /root/TunnelCore/v2ray/bin/v2ray/v2ray test -config "$cfg" >/tmp/tunnelcore-xray-test.log 2>&1
    fi
    if [[ "$?" = "0" ]]; then
    if [[ "$V2SEL_CORE" == "xray" ]]; then
    cp -f "$cfg" "/root/TunnelCore/v2ray/conf/config.${V2SEL_PORT}.json" 2>/dev/null || true
    else
    cp -f "$cfg" "/usr/local/etc/xray/config-${V2SEL_PORT}.json" 2>/dev/null || true
    ln -sf "/usr/local/etc/xray/config-${V2SEL_PORT}.json" "/usr/local/etc/xray/config.${V2SEL_PORT}.json" 2>/dev/null || true
    fi
    systemctl restart "$(v2ray_selected_unit "$V2SEL_PORT" "$V2SEL_CORE")" >/dev/null 2>&1
    systemctl enable "$(v2ray_selected_unit "$V2SEL_PORT" "$V2SEL_CORE")" >/dev/null 2>&1
    else
    echo -e "\033[1;31mEl JSON no paso la validacion de ${V2SEL_CORE}.\033[0m"
    sed -n '1,12p' /tmp/tunnelcore-xray-test.log 2>/dev/null
    pausa_v2ray
    return
    fi
    mkdir -p /etc/SSHPlus
    grep -q "$uuid" /etc/SSHPlus/RegV2ray 2>/dev/null || echo "  $uuid | $nick | $valid " >> /etc/SSHPlus/RegV2ray
    link_tls="$V2SEL_TLS"
    domain="$V2SEL_DOMAIN"
    path="$V2SEL_PATH"
    ext_port="$V2SEL_EXT_PORT"
    [[ -z "$ext_port" ]] && ext_port="$V2SEL_PORT"
    if [[ -z "$domain" || "$domain" == "local" || "$domain" == "You-HostName.com" ]]; then
    domain="$(cat /etc/SSHPlus/IP 2>/dev/null || cat /etc/IP 2>/dev/null || v2ray_public_ip)"
    fi
    add_host="$domain"
    host_header=""
    sni=""
    if [[ "$link_tls" == "tls" ]]; then
    if [[ "$V2SEL_SNI" == "You-HostName.com" || "$V2SEL_SNI" == "local" ]]; then
    V2SEL_SNI=""
    fi
    sni="${V2SEL_SNI:-$domain}"
    host_header="$sni"
    fi
    allow_insecure="false"
    if [[ "$V2SEL_CORE" == "xray" && "$network" == "xhttp" && "$link_tls" == "tls" ]]; then
    add_host="local"
    sni="local"
    host_header="You-HostName.com"
    allow_insecure="false"
    elif [[ "$link_tls" == "tls" ]]; then
    echo -ne "${SSHPlus_DARK_GREEN}Permitir certificado local/no verificado? [s/N]:${SCOLOR} "
    read insecure_opt
    [[ "$insecure_opt" =~ ^[sS]$ ]] && allow_insecure="true"
    fi
    enc_path="$(v2ray_urlencode_path "$path")"
    if [[ "$proto" == "vmess" ]]; then
    local tls_value="" json_alpn="" json_fp=""
    [[ "$link_tls" == "tls" ]] && tls_value="tls"
    if [[ "$link_tls" == "tls" ]]; then
    json_fp="chrome"
    [[ "$network" == "xhttp" ]] && json_alpn="h2"
    fi
    vmess_json=$(cat <<EOF
{"v":"2","ps":"${nick}","add":"${add_host}","port":"${ext_port}","id":"${uuid}","aid":"0","scy":"auto","net":"${network}","type":"","host":"${host_header}","path":"${path}","tls":"${tls_value}","sni":"${sni}","alpn":"${json_alpn}","fp":"${json_fp}","allowInsecure":"${allow_insecure}"}
EOF
)
    vmess_b64="$(printf '%s' "$vmess_json" | base64 -w 0 2>/dev/null || printf '%s' "$vmess_json" | base64 | tr -d '\n')"
    uri="vmess://${vmess_b64}"
    else
    if [[ "$link_tls" == "tls" ]]; then
    if [[ "$network" == "xhttp" ]]; then
    uri="vless://${uuid}@${add_host}:${ext_port}?encryption=none&type=xhttp&security=tls&sni=${sni}&host=${host_header}&path=${enc_path}&mode=packet-up#${nick}"
    else
    uri="vless://${uuid}@${add_host}:${ext_port}?type=${network}&security=tls&sni=${sni}&host=${host_header}&path=${enc_path}#${nick}"
    fi
    else
    if [[ "$network" == "xhttp" ]]; then
    uri="vless://${uuid}@${add_host}:${ext_port}?encryption=none&type=xhttp&security=none&path=${enc_path}&mode=packet-up#${nick}"
    else
    uri="vless://${uuid}@${add_host}:${ext_port}?type=${network}&security=none&path=${enc_path}#${nick}"
    fi
    fi
    fi
    clear
    v2ray_title "Nuevo Usuario ${V2SEL_CORE:-v2ray} ${proto} ${link_tls}"
    printf "\033[1;33mSERVICIO:\033[0m \033[1;37m%s\033[0m\n" "${V2SEL_CORE:-v2ray}"
    printf "\033[1;33mPROTOCOLO:\033[0m \033[1;37m%s\033[0m\n" "$proto"
    printf "\033[1;33mNOMBRE:\033[0m \033[1;37m%s\033[0m\n" "$nick"
    printf "\033[1;33mUUID:\033[0m \033[1;37m%s\033[0m\n" "$uuid"
    printf "\033[1;33mEXPIRA EN:\033[0m \033[1;37m%s\033[0m\n" "$days"
    v2ray_line
    echo -e "\033[1;36m${uri}\033[0m"
    v2ray_line
    echo -ne "${SSHPlus_DARK_GREEN}Ver cliente json? [S/N]:${SCOLOR} "
    read view_json
    if [[ "$view_json" =~ ^[sS]$ ]]; then
    echo ""
    if [[ "$proto" == "vmess" ]]; then
    jq -n --arg address "$add_host" --arg port "$ext_port" --arg id "$uuid" --arg network "$network" --arg security "$link_tls" --arg path "$path" --arg host "$host_header" --arg sni "${sni:-You-HostName.com}" --argjson allowInsecure "$allow_insecure" '{
      log: {
        loglevel: "debug"
      },
      inbounds: [
        {
          listen: "127.0.0.1",
          port: "1080",
          protocol: "socks",
          settings: {
            udp: true
          },
          tag: "socks"
        }
      ],
      outbounds: [
        {
          protocol: "vmess",
          settings: {
            vnext: [
              {
                address: $address,
                port: ($port | tonumber),
                users: [
                  {
                    id: $id,
                    alterId: 0,
                    security: "auto"
                  }
                ]
              }
            ]
          },
          streamSettings: ({
            network: $network,
            security: (if $security == "tls" then "tls" else "none" end)
          }
          + (
            if $network == "xhttp" then {
              xhttpSettings: {
                host: $host,
                path: $path,
                mode: "packet-up"
              }
            } elif $network == "grpc" then {
              grpcSettings: {
                serviceName: $path
              }
            } elif $network == "ws" then {
              wsSettings: {
                headers: {
                  Host: $host
                },
                path: $path
              }
            } else {} end
          )
          + (
            if $security == "tls" then {
              tlsSettings: ({
                allowInsecure: $allowInsecure,
                fingerprint: "chrome",
                serverName: $sni
              } + (if $network == "xhttp" then {alpn: ["h2"]} else {} end))
            } else {} end
          ))
        }
      ]
    }'
    else
    jq -n --arg address "$add_host" --arg port "$ext_port" --arg id "$uuid" --arg network "$network" --arg security "$link_tls" --arg path "$path" --arg host "$host_header" --arg sni "${sni:-You-HostName.com}" --argjson allowInsecure "$allow_insecure" '{
      log: {
        loglevel: "debug"
      },
      inbounds: [
        {
          listen: "127.0.0.1",
          port: "1080",
          protocol: "socks",
          settings: {
            udp: true
          },
          tag: "socks"
        }
      ],
      outbounds: [
        {
          protocol: "vless",
          settings: {
            vnext: [
              {
                address: $address,
                port: ($port | tonumber),
                users: [
                  {
                    id: $id,
                    encryption: "none"
                  }
                ]
              }
            ]
          },
          streamSettings: ({
            network: $network,
            security: (if $security == "tls" then "tls" else "none" end)
          }
          + (
            if $network == "xhttp" then {
              xhttpSettings: {
                host: $host,
                path: $path,
                mode: "packet-up"
              }
            } elif $network == "grpc" then {
              grpcSettings: {
                serviceName: $path
              }
            } elif $network == "ws" then {
              wsSettings: {
                headers: {
                  Host: $host
                },
                path: $path
              }
            } else {} end
          )
          + (
            if $security == "tls" then {
              tlsSettings: ({
                allowInsecure: $allowInsecure,
                fingerprint: "chrome",
                serverName: $sni
              } + (if $network == "xhttp" then {alpn: ["h2"]} else {} end))
            } else {} end
          ))
        }
      ]
    }'
    fi
    fi
    pausa_v2ray
    return
    }

    renewusr() {
    clear
    v2ray_title "RENOVAR USUARIO V2RAY/XRAY"
    [[ ! -s /etc/SSHPlus/RegV2ray ]] && echo -e "\033[1;31mNo hay usuarios V2RAY registrados.\033[0m" && pausa_v2ray && return
    local uuid_list user_list line_list user_sel days new_date
    mapfile -t uuid_list < <(awk -F'|' '{gsub(/^ +| +$/,"",$1); if($1!="") print $1}' /etc/SSHPlus/RegV2ray)
    mapfile -t user_list < <(awk -F'|' '{gsub(/^ +| +$/,"",$2); if($1!="") print $2}' /etc/SSHPlus/RegV2ray)
    mapfile -t line_list < <(awk -F'|' '{gsub(/^ +| +$/,"",$1); if($1!="") print NR}' /etc/SSHPlus/RegV2ray)
    for i in "${!uuid_list[@]}"; do
    v2ray_opt "$((i+1))" "${user_list[$i]} | ${uuid_list[$i]}"
    done
    v2ray_line
    v2ray_opt "0" "CANCELAR"
    v2ray_line
    echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} "
    read user_sel
    [[ "$user_sel" = "0" ]] && return
    if [[ ! "$user_sel" =~ ^[0-9]+$ || "$user_sel" -lt 1 || "$user_sel" -gt "${#uuid_list[@]}" ]]; then
    echo -e "\033[1;31mOpcion no valida!\033[0m"
    pausa_v2ray
    return
    fi
    echo -ne "${SSHPlus_DARK_GREEN}NUEVOS DIAS:${SCOLOR} "
    read days
    [[ -z "$days" ]] && days="30"
    if [[ ! "$days" =~ ^[0-9]+$ ]]; then
    echo -e "\033[1;31mDias no validos.\033[0m"
    pausa_v2ray
    return
    fi
    new_date="$(date '+%Y-%m-%d' -d "+${days} days" 2>/dev/null || date '+%Y-%m-%d')"
    sed -i "${line_list[$((user_sel-1))]}s#|[^|]*\$#| $new_date #" /etc/SSHPlus/RegV2ray
    echo -e "\033[1;32mUsuario renovado hasta: \033[1;37m$new_date\033[0m"
    pausa_v2ray
    return
    }

    menu_xray_xhttp() {
    clear
    if ! xhttp_is_installed; then
    v2ray_title "GESTION XRAY XHTTP [NO INSTALADO]"
    v2ray_opt "1" "INSTALAR XRAY XHTTP"
    v2ray_line
    v2ray_opt "0" "VOLVER"
    v2ray_line
    selection=$(selection_fun 1)
    case ${selection} in
      1)instalar_xray_xhttp ;;
      0)return ;;
    esac
    else
    local xport="$(jq -r '.inbounds[0].port // "8443"' /usr/local/etc/xray/config.json 2>/dev/null)"
    local xstatus="ACTIVO"
    systemctl is-active xray >/dev/null 2>&1 || xstatus="DETENIDO"
    v2ray_title "GESTION XRAY XHTTP [$xstatus - PUERTO: $xport]"
    v2ray_opt "1" "VER DATOS DE CONEXION / LINK VLESS"
    v2ray_opt "2" "CAMBIAR PUERTO XHTTP"
    v2ray_opt "3" "CAMBIAR PATH XHTTP"
    v2ray_opt "4" "CAMBIAR UUID / CLIENTE"
    v2ray_opt "5" "REINICIAR SERVICIO XRAY"
    v2ray_opt "6" "MODIFICAR JSON MANUALMENTE (nano/vi)"
    v2ray_opt "7" "DESINSTALAR XRAY XHTTP"
    v2ray_line
    v2ray_opt "0" "VOLVER"
    v2ray_line
    selection=$(selection_fun 7)
    case ${selection} in
      1)info_xray_xhttp ;;
      2)cambiar_puerto_xhttp ;;
      3)cambiar_path_xhttp ;;
      4)cambiar_uuid_xhttp ;;
      5)reiniciar_xray_xhttp ;;
      6)editar_json_xhttp ;;
      7)desinstalar_xray_xhttp ;;
      0)return ;;
    esac
    fi
    }
    menu_usuarios_v2ray() {
        while true; do
            clear
            v2ray_title "ADMINISTRADOR DE USUARIOS V2RAY/XRAY"
            v2ray_opt "1" "AGREGAR USUARIO"
            v2ray_opt "2" "ELIMINAR USUARIO"
            v2ray_opt "3" "RENOVAR USUARIO"
            v2ray_opt "4" "INFORMACION DE USUARIO"
            v2ray_opt "5" "CAMBIAR UID"
            v2ray_opt "6" "CAMBIAR PATH"
            v2ray_line
            v2ray_opt "0" "VOLVER"
            v2ray_line
            tput civis
            echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} "
            read usropt
            tput cnorm
            case "$usropt" in
                1 | 01) addusr ;;
                2 | 02) delusr ;;
                3 | 03) renewusr ;;
                4 | 04) mosusr_kk ;;
                5 | 05) modificar_uuid_v2ray ;;
                6 | 06) modificar_path_v2ray ;;
                0 | 00) break ;;
                *) echo -e "\033[1;31mOpcion no valida!\033[0m"; sleep 1 ;;
            esac
        done
    }

    ajustes_v2ray() {
    clear
    v2ray_title "CONFIGURACION DE V2RAY"
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
    selection=$(selection_fun 7)
    case ${selection} in
    1)protocolv2ray ;;
    2)tls ;;
    3)portv ;;
    4)editar_json_v2ray ;;
    5)modificar_uuid_v2ray ;;
    6)modificar_path_v2ray ;;
    7)agregar_puerto_v2ray ;;
    0)return ;;
    esac
    }

    reiniciar_v2ray() {
    clear
    v2ray_title "REINICIAR SERVICIO V2RAY"
    if systemctl is-active xray >/dev/null 2>&1; then
    systemctl restart xray >/dev/null 2>&1
    else
    v2ray_restart_service
    fi
    echo -e "\033[1;32mServicio V2RAY reiniciado correctamente.\033[0m"
    v2ray_line
    echo -e "\033[1;37m* \033[1;33mEnter para continuar\033[0m" && read enter

    }

    fun_v2raymanager() {
        local ports service_on toggle_status x
        while true; do
            clear
            ports="$(v2ray_ports_configured)"
            if v2ray_service_running; then
                service_on=1
            else
                service_on=0
            fi
            if [[ -z "$ports" ]]; then
                v2ray_title "V2RAY/XRAY"
                v2ray_opt "1" "INSTALAR V2RAY/XRAY"
                v2ray_opt "0" "Volver"
                v2ray_line
                echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} "
                read x
                case $x in
                  1 | 01) intallv2ray ;;
                  0 | 00) break ;;
                  *) echo -e "\033[1;31mOpcion no valida!\033[0m"; sleep 2 ;;
                esac
                continue
            fi

            [[ "$service_on" = "1" ]] && toggle_status="\033[1;32mo\033[0m" || toggle_status="\033[1;31mx\033[0m"
            v2ray_title "CONFIGURACION V2RAY / XRAY"
            v2ray_opt "1" "ADMINISTRADOR DE USUARIOS V2RAY/XRAY"
            v2ray_opt "2" "AGREGAR PROTOCOLO V2RAY/XRAY"
            v2ray_opt "3" "QUITAR PROTOCOLO V2RAY/XRAY"
            v2ray_opt "4" "VER CONFIGURACION JSON"
            v2ray_opt "5" "EDITAR CONFIGURACION JSON (nano)"
            v2ray_opt "6" "ESTADO DEL SERVICIO"
            v2ray_opt "7" "REINICIAR SERVICIO"
            v2ray_opt "8" "INICIAR/DETENER SERVICIO" "  $toggle_status"
            v2ray_opt "9" "VOLVER A CONFIGURAR"
            v2ray_opt "10" "DESINTALAR V2RAY"
            v2ray_opt "0" "VOLVER"
            v2ray_line
            echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} "
            read x
            clear
            case $x in
            1 | 01) menu_usuarios_v2ray ;;
            2 | 02) crear_protocolo_v2ray ;;
            3 | 03) v2ray_delete_protocol ;;
            4 | 04) v2ray_show_port_json ;;
            5 | 05) v2ray_edit_port_json ;;
            6 | 06) v2ray_services_status ;;
            7 | 07) v2ray_restart_all_services ;;
            8 | 08) v2ray_toggle_all_services ;;
            9 | 09) crear_protocolo_v2ray ;;
            10) unistallv2 ;;
            0 | 00) break ;;
            *) echo -e "\033[1;31mOpcion no valida!\033[0m"; sleep 2 ;;
            esac
        done
    }


tc_xray_menu() {
    fun_v2raymanager "$@"
}

tc_v2ray_users_menu() {
    menu_usuarios_v2ray "$@"
}
