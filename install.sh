#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — Instalador Automático
#  Uso: bash <(curl -fsSL https://raw.githubusercontent.com/Davidgelves/TunnelCore/main/install.sh)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

export DEBIAN_FRONTEND=noninteractive

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;38;2;76;228;255m'
WHITE='\033[1;37m'
NC='\033[0m'

clear
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}                INSTALADOR TUNNELCORE v1.0.0               ${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# 1. Verificar root
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo -e "${RED}[✗] Debe ejecutarse como usuario root.${NC}"
    exit 1
fi

# 2. Instalar dependencias esenciales
echo -e "${YELLOW}[*] Actualizando repositorios e instalando paquetes necesarios...${NC}"
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y curl wget git python3 unzip jq iptables net-tools ca-certificates >/dev/null 2>&1 || {
    echo -e "${RED}[✗] Error instalando paquetes de sistema.${NC}"
    exit 1
}

# 3. Directorio de instalación
INSTALL_DIR="/opt/tunnelcore"
REPO_URL="${TC_INSTALL_REPO:-https://github.com/Davidgelves/TunnelCore.git}"

echo -e "${YELLOW}[*] Descargando archivos de TunnelCore...${NC}"
rm -rf "$INSTALL_DIR"
if git clone --depth=1 "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] Repositorio clonado con éxito.${NC}"
else
    # Fallback con tarball si git falla
    mkdir -p "$INSTALL_DIR"
    curl -fsSL "https://github.com/Davidgelves/TunnelCore/archive/refs/heads/main.tar.gz" -o /tmp/tc.tar.gz 2>/dev/null || true
    if [[ -s /tmp/tc.tar.gz ]]; then
        tar -xzf /tmp/tc.tar.gz -C /tmp
        cp -rf /tmp/TunnelCore-main/* "$INSTALL_DIR/" 2>/dev/null || true
        rm -rf /tmp/tc.tar.gz /tmp/TunnelCore-main
    else
        echo -e "${RED}[✗] Error descargando TunnelCore.${NC}"
        exit 1
    fi
fi

# 4. Permisos y enlaces simbólicos (para ejecutar con 'tunnelcore' o 'menu')
chmod -R +x "${INSTALL_DIR}"
ln -sf "${INSTALL_DIR}/tunnelcore" /usr/local/bin/tunnelcore
ln -sf "${INSTALL_DIR}/tunnelcore" /usr/bin/tunnelcore 2>/dev/null || true
ln -sf "${INSTALL_DIR}/tunnelcore" /bin/tunnelcore 2>/dev/null || true

ln -sf "${INSTALL_DIR}/tunnelcore" /usr/local/bin/menu
ln -sf "${INSTALL_DIR}/tunnelcore" /usr/bin/menu 2>/dev/null || true
ln -sf "${INSTALL_DIR}/tunnelcore" /bin/menu 2>/dev/null || true

# Configurar alias en .bashrc
if ! grep -q "alias menu=" /root/.bashrc 2>/dev/null; then
    echo "alias menu='tunnelcore'" >> /root/.bashrc
fi

# 5. Directorios de configuración
mkdir -p /etc/tunnelcore/passwords /etc/tunnelcore/backups
chmod 700 /etc/tunnelcore/passwords
[[ -f /etc/tunnelcore/users.db ]] || touch /etc/tunnelcore/users.db
chmod 600 /etc/tunnelcore/users.db

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}        ¡TUNNELCORE INSTALADO CORRECTAMENTE!               ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${WHITE}Para abrir el menú en cualquier momento, escriba:${NC} ${CYAN}menu${NC} ${WHITE}o${NC} ${CYAN}tunnelcore${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
sleep 1

# 6. Lanzar menú
/usr/local/bin/tunnelcore

