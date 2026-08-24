# TunnelCore

Gestión de VPS / SSH / Tunneling — Modular, limpio, sin errores heredados.

## Instalación Rápida

Ejecute en su VPS como usuario `root`:

```bash
wget -qO tunnelcore "https://raw.githubusercontent.com/Davidgelves/TunnelCore/main/install.sh?$(date +%s)" && chmod +x tunnelcore && bash tunnelcore
```

O también con `curl`:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Davidgelves/TunnelCore/main/install.sh?$(date +%s)")
```

## Estructura

```
TunnelCore/
├── tunnelcore          # Punto de entrada principal
├── core/               # Librerías compartidas
│   ├── ui.sh           # Colores, menú, prompts
│   ├── utils.sh        # Validaciones, detección de sistema
│   └── config.sh       # Configuración persistente
├── modules/            # Módulos funcionales (en desarrollo)
│   ├── users.sh        # Gestión de usuarios
│   ├── protocols/      # Protocolos de conexión
│   │   ├── v2ray.sh
│   │   ├── slowdns.sh
│   │   ├── hysteria.sh
│   │   └── ...
│   └── ...
└── config/             # Datos persistentes (/etc/tunnelcore)
```

## Requisitos

- Ubuntu 18.04+ / Debian 9+
- Root access
- bash 4.0+

## Protocolos Soportados

| Protocolo | Fuente Oficial | Estado |
|-----------|---------------|--------|
| Xray (V2Ray) | [XTLS/Xray-core](https://github.com/XTLS/Xray-core) | 🔜 Próximo |
| SlowDNS | [dnstt](https://www.bamsoftware.com/software/dnstt/) | 🔜 Próximo |
| Hysteria v1/v2 | [apernet/hysteria](https://github.com/apernet/hysteria) | 🔜 Próximo |
| BadVPN | [ambrop72/badvpn](https://github.com/ambrop72/badvpn) | 🔜 Próximo |
| Proxy SOCKS | Python integrado | 🔜 Próximo |
| WebSocket SSH | Python integrado | 🔜 Próximo |
| Stunnel | `apt: stunnel4` | 🔜 Próximo |
| Squid | `apt: squid` | 🔜 Próximo |
| Dropbear | `apt: dropbear` | 🔜 Próximo |

## Autor

**J DAVID AG** — [@Davidgelves](https://github.com/Davidgelves)

## Licencia

MIT
