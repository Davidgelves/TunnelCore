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
tc_xray_status_mark() {
    if v2ray_service_running; then
    printf '\033[1;32mo\033[0m'
    else
    printf '\033[1;31mx\033[0m'
    fi
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
    echo -e "\033[1;37mTunnelCore instalara Xray-core nativo para VLESS XHTTP.\033[0m"
    echo -e "\033[1;33mEste modo no depende del instalador externo antiguo de V2Ray.\033[0m"
    pausa_v2ray
    instalar_xray_xhttp
    return
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
    source <(curl -sL https://multi.netlify.app/v2ray.sh) --remove > /dev/null 2>&1
    systemctl stop xray >/dev/null 2>&1
    systemctl disable xray >/dev/null 2>&1
    rm -f /etc/systemd/system/xray.service /usr/local/bin/xray /usr/bin/xray /bin/xray >/dev/null 2>&1
    rm -rf /usr/local/etc/xray /etc/xray /var/log/xray >/dev/null 2>&1
    systemctl daemon-reload >/dev/null 2>&1
    rm -rf /etc/SSHPlus/RegV2ray > /dev/null 2>&1
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
    v2ray_title "ANADIR USUARIO | UUID V2RAY"
    local cfg tmp
    cfg="$(v2ray_config_file)"
    [[ -z "$cfg" ]] && echo -e "\033[1;31mNo se encontro config.json de V2Ray/Xray.\033[0m" && pausa_v2ray && fun_v2raymanager
    v2ray_ensure_legacy_config "$cfg"
    cfg="/etc/v2ray/config.json"
    if ! v2ray_require_jq; then
        echo -e "\033[1;31mjq no esta instalado; no se puede modificar el JSON de forma segura.\033[0m"
        echo -e "\033[1;37mInstale jq y vuelva a intentar crear el usuario V2Ray.\033[0m"
        pausa_v2ray
        fun_v2raymanager
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
        local vmess_b64="$(printf '%s' "$vmess_json" | base64 -w 0 2>/dev/null || printf '%s' "$vmess_json" | base64 | tr -d '\n')"
        uri="vmess://${vmess_b64}"
    else
        local enc_path="$(v2ray_urlencode_path "$path_ws")"
        local link_network="$inbound_network"
        [[ -z "$link_network" || "$link_network" == "null" || "$link_network" == "tcp" ]] && link_network="ws"
        if [[ "$tls_mode" == "tls" ]]; then
            uri="vless://${UUID}@${add_host}:${ext_port}?type=${link_network}&security=tls&sni=${sni_host}&host=${host_header}&path=${enc_path}#${nick}"
        else
            uri="vless://${UUID}@${add_host}:${ext_port}?type=${link_network}&security=none&path=${enc_path}#${nick}"
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
    [[ ! -s /etc/SSHPlus/RegV2ray ]] && echo -e "\033[1;31mNo hay usuarios V2RAY registrados.\033[0m" && pausa_v2ray && fun_v2raymanager
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
    [[ "$uuid_sel" = "0" ]] && fun_v2raymanager
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
          "path": "${path}"
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
    echo -e "\033[1;37mvless://${uuid}@${host}:${port}?security=none&type=xhttp&path=$(v2ray_urlencode_path "$path")#TunnelCore-XHTTP\033[0m"
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

    crear_protocolo_v2ray() {
    local opt proto network tls link_tls port ext_port path domain host_header sni uuid user exp cfg uri enc_path vmess_json vmess_b64
    clear
    v2ray_title "CREAR PROTOCOLO V2RAY / XRAY"
    if ! xhttp_is_installed; then
    echo -e "\033[1;33mXray-core no esta instalado. Primero se abrira el instalador base.\033[0m"
    pausa_v2ray
    instalar_xray_xhttp
    return
    fi
    v2ray_opt "1" "VLESS + WebSocket CDN TLS 443"
    v2ray_opt "2" "VLESS + WebSocket sin TLS 80"
    v2ray_opt "3" "VMess + WebSocket sin TLS 80"
    v2ray_opt "4" "VLESS + XHTTP sin TLS 8443"
    v2ray_line
    v2ray_opt "0" "VOLVER"
    v2ray_line
    selection=$(selection_fun 4)
    [[ "$selection" = "0" ]] && fun_v2raymanager && return

    case "$selection" in
      1) proto="vless"; network="ws"; tls="none"; link_tls="tls"; port="80"; ext_port="443"; path="/v2ray" ;;
      2) proto="vless"; network="ws"; tls="none"; link_tls="none"; port="80"; ext_port="80"; path="/v2ray" ;;
      3) proto="vmess"; network="ws"; tls="none"; link_tls="none"; port="80"; ext_port="80"; path="/v2ray" ;;
      4) proto="vless"; network="xhttp"; tls="none"; link_tls="none"; port="8443"; ext_port="8443"; path="/xhttp" ;;
    esac

    echo -ne "${SSHPlus_DARK_GREEN}USUARIO [Enter = user]:${SCOLOR} " && read user
    user="$(printf '%s' "$user" | sed -e 's/[^a-zA-Z0-9_. -]//g')"
    [[ -z "$user" ]] && user="user"
    echo -ne "${SSHPlus_DARK_GREEN}PUERTO [Enter = $port]:${SCOLOR} " && read custom_port
    [[ -n "$custom_port" ]] && port="$custom_port"
    [[ "$link_tls" == "none" ]] && ext_port="$port"
    if ! v2ray_valid_port "$port"; then
    echo -e "\033[1;31mPuerto no valido. Use 1-65535.\033[0m"
    pausa_v2ray
    fun_v2raymanager
    return
    fi
    echo -ne "${SSHPlus_DARK_GREEN}PATH [Enter = $path]:${SCOLOR} " && read custom_path
    [[ -n "$custom_path" ]] && path="$custom_path"
    path="$(printf '%s' "$path" | tr -d '"\\[:space:]')"
    [[ "$path" != /* ]] && path="/$path"

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
    exp="$(date '+%Y-%m-%d' -d '+365 days' 2>/dev/null || date '+%Y-%m-%d')"
    cfg="/usr/local/etc/xray/config.json"
    mkdir -p /usr/local/etc/xray /etc/SSHPlus/v2ray /etc/v2ray /etc/SSHPlus
    [[ -f "$cfg" ]] && cp "$cfg" "$cfg.bak-$(date +%s)"

    if [[ "$proto" == "vmess" ]]; then
    cat > "$cfg" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "vmess-ws",
      "listen": "0.0.0.0",
      "port": ${port},
      "protocol": "vmess",
      "settings": {
        "clients": [
          { "id": "${uuid}", "alterId": 0 }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "${path}" }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" }
  ]
}
EOF
    else
    cat > "$cfg" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "${proto}-${network}",
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
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" }
  ]
}
EOF
    fi

    ln -sf "$cfg" /etc/v2ray/config.json 2>/dev/null || true
    if /usr/local/bin/xray test -config "$cfg" >/dev/null 2>&1; then
    systemctl restart xray >/dev/null 2>&1
    else
    echo -e "\033[1;31mEl config.json generado no paso la validacion de Xray.\033[0m"
    pausa_v2ray
    fun_v2raymanager
    return
    fi
    grep -q "$uuid" /etc/SSHPlus/RegV2ray 2>/dev/null || echo "  $uuid | $user | $exp " >> /etc/SSHPlus/RegV2ray

    enc_path="$(v2ray_urlencode_path "$path")"
    if [[ "$proto" == "vmess" ]]; then
    vmess_json=$(cat <<EOF
{"v":"2","ps":"${user}","add":"${domain}","port":"${port}","id":"${uuid}","aid":"0","scy":"auto","net":"ws","type":"","host":"","path":"${path}","tls":"","sni":"","alpn":"","fp":""}
EOF
)
    vmess_b64="$(printf '%s' "$vmess_json" | base64 -w 0 2>/dev/null || printf '%s' "$vmess_json" | base64 | tr -d '\n')"
    uri="vmess://${vmess_b64}"
    elif [[ "$link_tls" == "tls" ]]; then
    uri="vless://${uuid}@${domain}:${ext_port}?type=${network}&security=tls&sni=${sni}&host=${host_header}&path=${enc_path}#${user}"
    else
    uri="vless://${uuid}@${domain}:${ext_port}?type=${network}&security=none&path=${enc_path}#${user}"
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
    v2ray_line
    echo -e "\033[1;33mLINK PARA IMPORTAR:\033[0m"
    echo -e "\033[1;36m${uri}\033[0m"
    v2ray_line
    pausa_v2ray
    fun_v2raymanager
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
      0)fun_v2raymanager ;;
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
      0)fun_v2raymanager ;;
    esac
    fi
    }
    menu_usuarios_v2ray() {
        while true; do
            clear
            v2ray_title "ADMINISTRAR USUARIOS V2RAY"
            v2ray_opt "1" "ANADIR USUARIO | UUID"
            v2ray_opt "2" "ELIMINAR USUARIO V2RAY"
            v2ray_opt "3" "USUARIOS REGISTRADOS"
            v2ray_opt "4" "INFORMACION DE CUENTA"
            v2ray_opt "5" "LIMITAR MB POR PUERTO / UUID"
            v2ray_opt "6" "ESTADISTICAS DE CONSUMO"
            v2ray_opt "7" "LIMPIAR USUARIOS EXPIRADOS"
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
                3 | 03) mosusr_kk ;;
                4 | 04) infocuenta ;;
                5 | 05) lim_port ;;
                6 | 06) stats ;;
                7 | 07) limpiador_activador ;;
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
    0)fun_v2raymanager ;;
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
        while true; do
            clear
            v2ray_title "V2RAY"
            if v2ray_service_running; then
                v2ray_running=1
            else
                v2ray_running=0
            fi
            xv2ray1=`if [[ "$v2ray_running" = "1" ]]; then
            echo -e "\e[92m ACTIVADO"
            else
            echo -e "\e[91m DESACTIVADO"
            fi`;
            echo -e "${SSHPlus_DARK_GREEN}SERVICIO:${SCOLOR} \033[1;33mV2RAY \033[1;32m$xv2ray1\033[1;37m"
            xv2ray=`if [[ "$v2ray_running" = "1" ]]; then
            echo -e "\033[1;32mo "
            else
            echo -e "\033[1;31mx "
            fi`;
            v2ray_line
            if [[ "$v2ray_running" = "1" ]]; then
                v2ray_opt "1" "INSTALAR / REINSTALAR XRAY-CORE" "$xv2ray"
                v2ray_opt "2" "CREAR PROTOCOLO"
                v2ray_opt "3" "ADMINISTRAR USUARIOS"
                v2ray_opt "4" "VER DATOS / LINKS"
                v2ray_opt "5" "CONFIGURACION AVANZADA"
                v2ray_opt "6" "REINICIAR SERVICIO XRAY"
                v2ray_opt "7" "DESINSTALAR XRAY / V2RAY"
                v2ray_opt "0" "VOLVER"
            else
                v2ray_opt "1" "INSTALAR XRAY-CORE / MOTOR V2RAY" "$xv2ray"
                v2ray_opt "2" "CREAR PROTOCOLO"
                v2ray_opt "0" "VOLVER"
            fi
            v2ray_line
            tput civis
            echo -ne "${SSHPlus_CYAN}Opcion:${SCOLOR} "
            read x
            tput cnorm
            clear
            if [[ "$v2ray_running" != "1" ]]; then
                case $x in
                1 | 01)
                    intallv2ray
                    ;;
                2 | 02)
                    crear_protocolo_v2ray
                    ;;
                0 | 00)
                    break
                    ;;
                *)
                    echo -e "\033[1;31mOpcion no valida!\033[0m"
                    sleep 2
                    ;;
                esac
                continue
            fi
            case $x in
            1 | 01)
                intallv2ray
                ;;
            2 | 02)
                crear_protocolo_v2ray
                ;;
            3 | 03)
                menu_usuarios_v2ray
                ;;
            4 | 04)
                infocuenta
                ;;
            5 | 05)
                ajustes_v2ray
                ;;
            6 | 06)
                reiniciar_v2ray
                ;;
            7 | 07)
                unistallv2
                ;;
            0 | 00)
                    break
                ;;
            *)
                echo -e "\033[1;31mOpcion no valida!\033[0m"
                sleep 2
                ;;
            esac
        done
    }


tc_xray_menu() {
    fun_v2raymanager "$@"
}
