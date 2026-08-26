#!/bin/bash
# TunnelCore — core/utils.sh
# Utilidades compartidas: validaciones, detección del sistema, descargas.

# ── Directorio base de datos ──────────────────────────────────
TC_DATA_DIR="/etc/tunnelcore"
TC_USERS_DB="${TC_DATA_DIR}/users.db"
TC_PASS_DIR="${TC_DATA_DIR}/passwords"

# ── Verificar root ────────────────────────────────────────────
tc_require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        tc_msg_err "Este script debe ejecutarse como root."
        tc_msg_warn "Use: sudo tunnelcore"
        exit 1
    fi
}

# ── Detección de OS ───────────────────────────────────────────
tc_detect_os() {
    # Retorna: ubuntu, debian, centos, o unknown
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID,,}" in
            ubuntu)  echo "ubuntu" ;;
            debian)  echo "debian" ;;
            centos)  echo "centos" ;;
            fedora)  echo "fedora" ;;
            *)       echo "${ID,,}" ;;
        esac
    else
        echo "unknown"
    fi
}

tc_os_version() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "${PRETTY_NAME:-${ID} ${VERSION_ID}}"
    elif [[ -f /etc/issue.net ]]; then
        head -1 /etc/issue.net
    else
        echo "Desconocido"
    fi
}

# ── Detección de arquitectura ─────────────────────────────────
tc_detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)       echo "amd64" ;;
        aarch64|arm64)      echo "arm64" ;;
        armv7l|armhf)       echo "arm" ;;
        i686|i386)          echo "386" ;;
        *)                  echo "unknown" ;;
    esac
}

# ── Detección de interfaz de red ──────────────────────────────
tc_detect_interface() {
    local iface
    # Método 1: ruta por defecto
    iface="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
    [[ -n "$iface" ]] && echo "$iface" && return 0
    # Método 2: primera interfaz UP que no sea lo
    iface="$(ip -o link show 2>/dev/null | awk -F': ' '/state UP/ && !/lo:/ {print $2; exit}')"
    [[ -n "$iface" ]] && echo "$iface" && return 0
    # Fallback
    echo "eth0"
}

# ── IP pública ────────────────────────────────────────────────
tc_public_ip() {
    local ip=""
    # Intentar múltiples fuentes
    for url in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
        ip="$(curl -4fsS --max-time 5 "$url" 2>/dev/null)" && break
    done
    [[ -z "$ip" ]] && ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    echo "${ip:-N/A}"
}

# ── Validación de puertos ─────────────────────────────────────
tc_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

tc_port_in_use() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -tlnp 2>/dev/null | grep -qE ":${port}[[:space:]]"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tlnp 2>/dev/null | grep -qE ":${port}[[:space:]]"
    else
        return 1
    fi
}

# ── Validación de UUID ────────────────────────────────────────
tc_valid_uuid() {
    [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

# ── Generar UUID ──────────────────────────────────────────────
tc_gen_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        # Fallback: generar con /dev/urandom
        local hex
        hex="$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')"
        printf '%s-%s-%s-%s-%s' \
            "${hex:0:8}" "${hex:8:4}" "${hex:12:4}" "${hex:16:4}" "${hex:20:12}"
    fi
}

# ── Información del sistema ───────────────────────────────────
tc_ram_total() {
    if command -v free >/dev/null 2>&1; then
        LC_ALL=C free -h 2>/dev/null | awk '/^Mem:/ {print $2}'
    else
        awk '/^MemTotal:/ {printf "%.1fGi", $2/1024/1024}' /proc/meminfo 2>/dev/null
    fi
}

tc_ram_percent() {
    if command -v free >/dev/null 2>&1; then
        LC_ALL=C free 2>/dev/null | awk '/^Mem:/ {if ($2>0) printf "%.1f%%", ($3/$2)*100; else print "N/A"}'
    else
        awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{if(t>0) printf "%.1f%%", ((t-a)/t)*100; else print "N/A"}' /proc/meminfo 2>/dev/null
    fi
}

tc_cpu_cores() {
    nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "?"
}

tc_cpu_percent() {
    # Lectura rápida de CPU usage sin top (que es lento)
    if [[ -f /proc/stat ]]; then
        local line1 line2
        read -r line1 < /proc/stat
        sleep 0.3
        read -r line2 < /proc/stat
        awk '{
            split(a, f1); split($0, f2)
            idle1=f1[5]+f1[6]; idle2=f2[5]+f2[6]
            total1=0; total2=0
            for(i=2;i<=NF;i++){total1+=f1[i]; total2+=f2[i]}
            dt=total2-total1; di=idle2-idle1
            if(dt>0) printf "%.1f%%", (1-di/dt)*100
            else print "N/A"
        }' a="$line1" <<< "$line2"
    else
        echo "N/A"
    fi
}

tc_system_time() {
    date '+%H:%M:%S'
}

# ── Conteo de usuarios ────────────────────────────────────────
tc_total_users() {
    if [[ -f "$TC_USERS_DB" ]]; then
        awk -F'|' 'NF && $1 ~ /[[:alnum:]_:-]/ {count++} END {print count+0}' "$TC_USERS_DB" 2>/dev/null
    else
        # Contar usuarios del sistema con UID >= 1000 y shell válido
        awk -F: '$3 >= 1000 && $7 !~ /nologin|false/ {count++} END {print count+0}' /etc/passwd 2>/dev/null
    fi
}

tc_connected_users() {
    local count=0 user conns
    if [[ -f "$TC_USERS_DB" ]]; then
        while IFS='|' read -r user _expiry _limit _created _rest; do
            user="$(echo "$user" | xargs)"
            [[ -z "$user" ]] && continue
            if declare -f tc_user_active_conns >/dev/null 2>&1; then
                conns="$(tc_user_active_conns "$user" 2>/dev/null)"
            else
                conns="$(ps -u "$user" 2>/dev/null | awk 'NR>1 {count++} END {print count+0}')"
            fi
            [[ "$conns" =~ ^[0-9]+$ ]] || conns=0
            (( conns > 0 )) && (( count++ ))
        done < "$TC_USERS_DB"
    else
        count="$(who 2>/dev/null | awk '{print $1}' | sort -u | wc -l | tr -d ' ')"
    fi
    echo "${count:-0}"
}

tc_expired_users() {
    local count=0 today_sec
    today_sec="$(date +%s)"
    if [[ -f "$TC_USERS_DB" ]]; then
        while IFS='|' read -r _user expiry _limit _created _rest; do
            expiry="$(echo "$expiry" | xargs)"
            [[ -z "$expiry" ]] && continue
            local exp_sec
            if [[ "$expiry" =~ ^test:([0-9]+):[0-9]+$ ]]; then
                exp_sec="${BASH_REMATCH[1]}"
            else
                exp_sec="$(date +%s --date="$expiry" 2>/dev/null)" || continue
            fi
            (( today_sec > exp_sec )) && (( count++ ))
        done < "$TC_USERS_DB"
    fi
    echo "$count"
}

# ── Descarga segura ───────────────────────────────────────────
tc_download() {
    # Uso: tc_download "URL" "DESTINO" [intentos]
    local url="$1" dest="$2" retries="${3:-3}" attempt=0
    while (( attempt < retries )); do
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --max-time 30 -o "$dest" "$url" 2>/dev/null && return 0
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "$dest" --timeout=30 "$url" 2>/dev/null && return 0
        else
            tc_msg_err "Necesita curl o wget instalado."
            return 1
        fi
        (( attempt++ ))
        sleep 2
    done
    return 1
}

# ── Instalación de paquetes ───────────────────────────────────
tc_apt_install() {
    # Uso: tc_apt_install paquete1 paquete2 ...
    export DEBIAN_FRONTEND=noninteractive
    if ! apt-get install -y "$@" >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y "$@" >/dev/null 2>&1
    fi
}

# ── Verificar que un comando exista ───────────────────────────
tc_require_cmd() {
    local cmd="$1" pkg="${2:-$1}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        tc_msg_warn "$cmd no encontrado. Instalando $pkg..."
        tc_apt_install "$pkg" || {
            tc_msg_err "No se pudo instalar $pkg."
            return 1
        }
    fi
}

# ── Backup de archivo ─────────────────────────────────────────
tc_backup_file() {
    local file="$1"
    [[ -f "$file" ]] && cp "$file" "${file}.bak-$(date +%s)"
}

# ── Generar password aleatorio ────────────────────────────────
tc_rand_string() {
    local len="${1:-16}"
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$len"
}
