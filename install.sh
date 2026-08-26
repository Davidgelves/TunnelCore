#!/bin/bash
# TunnelCore - Instalador automatico
# Uso: bash <(curl -fsSL https://raw.githubusercontent.com/Davidgelves/TunnelCore/main/install.sh)
# Autor: J DAVID AG

export DEBIAN_FRONTEND=noninteractive

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;38;2;76;228;255m'
WHITE='\033[1;37m'
NC='\033[0m'

tc_install_line() {
    echo -e "${CYAN}============================================================${NC}"
}

tc_install_step() {
    echo -e "${YELLOW}[*] $1${NC}"
}

TC_INSTALL_TOTAL=8
TC_INSTALL_CURRENT=0
tc_install_progress() {
    local label="$1" percent filled empty i
    TC_INSTALL_CURRENT=$((TC_INSTALL_CURRENT + 1))
    percent=$((TC_INSTALL_CURRENT * 100 / TC_INSTALL_TOTAL))
    filled=$((percent / 5))
    empty=$((20 - filled))
    printf "${CYAN}["
    for ((i=0; i<filled; i++)); do printf "#"; done
    for ((i=0; i<empty; i++)); do printf "."; done
    printf "] ${WHITE}%3s%%${NC} ${YELLOW}%s${NC}\n" "$percent" "$label"
}

tc_install_ok() {
    echo -e "${GREEN}[OK] $1${NC}"
}

tc_install_fail() {
    echo -e "${RED}[ERROR] $1${NC}"
}

tc_install_login_banner() {
    touch /root/.hushlogin 2>/dev/null || true
    cat > /etc/profile.d/tunnelcore.sh <<'EOF'
#!/bin/bash
case "$-" in
    *i*) ;;
    *) return 0 2>/dev/null || exit 0 ;;
esac
if [[ -n "${TUNNELCORE_BANNER_SHOWN:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
export TUNNELCORE_BANNER_SHOWN=1

TC_RED='\033[1;31m'
TC_GREEN='\033[1;32m'
TC_YELLOW='\033[1;33m'
TC_CYAN='\033[1;38;2;76;228;255m'
TC_WHITE='\033[1;37m'
TC_NC='\033[0m'
printf '%b' "${TC_CYAN}"
cat <<'BANNER'
 _______                     _  _____
|__   __|                   | |/ ____|
   | |_   _ _ __  _ __   ___| | |     ___  _ __ ___
   | | | | | '_ \| '_ \ / _ \ | |    / _ \| '__/ _ \
   | | |_| | | | | | | |  __/ | |___| (_) | | |  __/
   |_|\__,_|_| |_|_| |_|\___|_|\_____\___/|_|  \___|
BANNER
printf '%b\n%b            TUNNELCORE%b\n\n' "${TC_NC}" "${TC_CYAN}" "${TC_NC}"
printf '%b    Desarrollador: %bJ DAVID AG%b\n\n' "${TC_CYAN}" "${TC_WHITE}" "${TC_NC}"
printf '%b   Escriba %b"menu"%b para ingresar%b\n\n' "${TC_CYAN}" "${TC_WHITE}" "${TC_CYAN}" "${TC_NC}"
EOF
    chmod +x /etc/profile.d/tunnelcore.sh
    grep -qxF '. /etc/profile.d/tunnelcore.sh' /root/.bashrc 2>/dev/null || echo '. /etc/profile.d/tunnelcore.sh' >> /root/.bashrc
}

tc_install_os_name() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${PRETTY_NAME:-${ID} ${VERSION_ID}}"
    else
        echo "Linux"
    fi
}

clear
tc_install_line
echo -e "${CYAN}                INSTALADOR TUNNELCORE v1.0.0               ${NC}"
tc_install_line
echo ""

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    tc_install_fail "Debe ejecutarse como usuario root."
    exit 1
fi

tc_install_line
echo -e "${WHITE}                 Instalacion de dependencias                ${NC}"
echo -e "${YELLOW}                 $(tc_install_os_name)                      ${NC}"
tc_install_line

if ! command -v apt-get >/dev/null 2>&1; then
    tc_install_fail "Este instalador requiere Debian/Ubuntu con apt-get."
    exit 1
fi

tc_install_progress "Actualizando repositorios del sistema..."
apt-get update -y || true

tc_install_progress "Instalando paquetes necesarios..."
TC_PACKAGES=(curl wget git python3 unzip jq iptables net-tools ca-certificates openssl lsof libstdc++6 libcurl4-openssl-dev)
apt-get install -y "${TC_PACKAGES[@]}" || {
    tc_install_fail "No se pudieron instalar las dependencias base."
    echo -e "${WHITE}Paquetes requeridos:${NC} ${TC_PACKAGES[*]}"
    exit 1
}
tc_install_ok "Dependencias instaladas correctamente."

INSTALL_DIR="/opt/tunnelcore"
REPO_URL="${TC_INSTALL_REPO:-https://github.com/Davidgelves/TunnelCore.git}"

tc_install_progress "Descargando archivos de TunnelCore..."
rm -rf "$INSTALL_DIR"
if git clone --depth=1 "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1; then
    tc_install_ok "Repositorio clonado con exito."
else
    mkdir -p "$INSTALL_DIR"
    curl -fsSL "https://github.com/Davidgelves/TunnelCore/archive/refs/heads/main.tar.gz" -o /tmp/tc.tar.gz 2>/dev/null || true
    if [[ -s /tmp/tc.tar.gz ]]; then
        tar -xzf /tmp/tc.tar.gz -C /tmp
        cp -rf /tmp/TunnelCore-main/* "$INSTALL_DIR/" 2>/dev/null || true
        rm -rf /tmp/tc.tar.gz /tmp/TunnelCore-main
        tc_install_ok "Archivos descargados por tarball."
    else
        tc_install_fail "Error descargando TunnelCore."
        exit 1
    fi
fi

tc_install_progress "Configurando permisos y comandos del sistema..."
chmod -R +x "${INSTALL_DIR}"
chmod 755 "${INSTALL_DIR}/tunnelcore"
ln -sf "${INSTALL_DIR}/tunnelcore" /usr/local/bin/tunnelcore
ln -sf "${INSTALL_DIR}/tunnelcore" /usr/bin/tunnelcore 2>/dev/null || true
ln -sf "${INSTALL_DIR}/tunnelcore" /bin/tunnelcore 2>/dev/null || true
ln -sf "${INSTALL_DIR}/tunnelcore" /usr/local/bin/menu
ln -sf "${INSTALL_DIR}/tunnelcore" /usr/bin/menu 2>/dev/null || true
ln -sf "${INSTALL_DIR}/tunnelcore" /bin/menu 2>/dev/null || true

if ! grep -q "alias menu=" /root/.bashrc 2>/dev/null; then
    echo "alias menu='tunnelcore'" >> /root/.bashrc
fi
tc_install_progress "Instalando presentacion de bienvenida..."
tc_install_login_banner

tc_install_progress "Preparando directorios de configuracion..."
mkdir -p /etc/tunnelcore/passwords /etc/tunnelcore/backups /etc/tunnelcore/proxy
chmod 700 /etc/tunnelcore/passwords
[[ -f /etc/tunnelcore/users.db ]] || touch /etc/tunnelcore/users.db
chmod 600 /etc/tunnelcore/users.db

grep -qxF "/bin/false" /etc/shells 2>/dev/null || echo "/bin/false" >> /etc/shells
grep -qxF "/usr/sbin/nologin" /etc/shells 2>/dev/null || echo "/usr/sbin/nologin" >> /etc/shells

if [[ ! -f /etc/pam.d/dropbear ]]; then
    mkdir -p /etc/pam.d
    cat > /etc/pam.d/dropbear <<'EOF'
@include common-auth
@include common-account
@include common-password
@include common-session
EOF
fi

if [[ -f "${INSTALL_DIR}/modules/protocols/proxy_server.py" ]]; then
    tc_install_progress "Preparando servicios auxiliares..."
    cp -f "${INSTALL_DIR}/modules/protocols/proxy_server.py" /etc/tunnelcore/proxy/proxy_server.py
    chmod +x /etc/tunnelcore/proxy/proxy_server.py
else
    tc_install_progress "Preparando servicios auxiliares..."
fi

tc_install_progress "Aplicando reinicios necesarios..."
if systemctl is-active --quiet tunnelcore-proxy 2>/dev/null; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl restart tunnelcore-proxy >/dev/null 2>&1 || true
fi

if systemctl is-active --quiet dropbear 2>/dev/null; then
    systemctl restart dropbear >/dev/null 2>&1 || service dropbear restart >/dev/null 2>&1 || true
fi

echo ""
tc_install_line
echo -e "${GREEN}        TUNNELCORE INSTALADO CORRECTAMENTE                 ${NC}"
tc_install_line
echo -e "${WHITE}Para abrir el menu en cualquier momento, escriba:${NC} ${CYAN}menu${NC} ${WHITE}o${NC} ${CYAN}tunnelcore${NC}"
tc_install_line
echo ""
sleep 1

/usr/local/bin/tunnelcore
