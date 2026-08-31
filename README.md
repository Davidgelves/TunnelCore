# TunnelCore

Panel de gestion para VPS, SSH y tunneling.

TunnelCore esta pensado para instalarse y usarse directamente en un servidor VPS. Este repositorio no esta orientado a modificacion, redistribucion o reprogramacion del script.

## Sistemas compatibles

- Ubuntu 18.04 o superior
- Debian 9 o superior
- VPS con acceso root
- Sistemas basados en Debian/Ubuntu que usen `apt-get`

No se recomienda instalar en CentOS, Fedora, AlmaLinux, Rocky Linux, Arch Linux u otros sistemas que no usen `apt-get`.

## Instalacion

Ejecute en su VPS como usuario `root`:

```bash
wget -qO tunnelcore "https://gitlab.com/Davidgelves/tunnelcore/-/raw/main/install.sh?$(date +%s)" && chmod +x tunnelcore && bash tunnelcore
```

O tambien con `curl`:

```bash
bash <(curl -fsSL "https://gitlab.com/Davidgelves/tunnelcore/-/raw/main/install.sh?$(date +%s)")
```

## Requisitos

- Acceso root
- Bash 4.0+
- Conexion a internet
- Paquetes base instalados automaticamente por el instalador

## Uso

Despues de instalar, ejecute:

```bash
tunnelcore
```

Tambien puede abrir el panel con:

```bash
menu
```

## Protocolos y funciones

TunnelCore incluye opciones para administrar servicios y conexiones de VPS:

- SSH
- Dropbear
- Proxy
- WebSocket SSH
- Stunnel
- Squid
- BadVPN
- SlowDNS
- Hysteria
- Xray/V2Ray
- Administracion de usuarios
- Monitor de usuarios online
- Limitador de conexiones
- Herramientas de red y VPS

Algunos protocolos pueden requerir configuracion adicional desde el panel.

## Desinstalacion

En caso de fallo, bug o si desea retirar TunnelCore del VPS, ejecute como `root`:

```bash
systemctl stop tunnelcore-proxy 2>/dev/null || true
systemctl disable tunnelcore-proxy 2>/dev/null || true
rm -f /usr/local/bin/tunnelcore /usr/bin/tunnelcore /bin/tunnelcore /usr/local/bin/menu /usr/bin/menu /bin/menu
rm -f /etc/profile.d/tunnelcore.sh
sed -i "/alias menu='tunnelcore'/d" /root/.bashrc
sed -i "\|. /etc/profile.d/tunnelcore.sh|d" /root/.bashrc
rm -rf /opt/tunnelcore
```

Para borrar tambien datos guardados por TunnelCore, usuarios internos, backups y configuracion:

```bash
rm -rf /etc/tunnelcore
```

## Aviso

Este proyecto es de uso personal y su codigo no debe ser copiado, vendido, republicado o usado para crear versiones derivadas sin autorizacion del autor.

## Autor

**J DAVID AG** - [@Davidgelves](https://gitlab.com/Davidgelves)
