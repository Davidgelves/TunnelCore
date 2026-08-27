# TunnelCore

Panel de gestion para VPS, SSH y tunneling.

TunnelCore esta pensado para instalarse y usarse directamente en un servidor VPS. Este repositorio no esta orientado a modificacion, redistribucion o reprogramacion del script.

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

- Ubuntu 18.04+ o Debian 9+
- Acceso root
- Bash 4.0+

## Uso

Despues de instalar, ejecute:

```bash
tunnelcore
```

## Aviso

Este proyecto es de uso personal y su codigo no debe ser copiado, vendido, republicado o usado para crear versiones derivadas sin autorizacion del autor.

## Autor

**J DAVID AG** - [@Davidgelves](https://gitlab.com/Davidgelves)
