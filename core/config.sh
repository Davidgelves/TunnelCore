#!/bin/bash
# TunnelCore — core/config.sh
# Gestión de configuración persistente.

TC_CONF_DIR="/etc/tunnelcore"
TC_CONF_FILE="${TC_CONF_DIR}/tunnelcore.conf"

# ── Inicializar configuración ─────────────────────────────────
tc_config_init() {
    mkdir -p "$TC_CONF_DIR"
    if [[ ! -f "$TC_CONF_FILE" ]]; then
        cat > "$TC_CONF_FILE" <<'EOF'
# TunnelCore — Configuración
# Generado automáticamente. Editar con precaución.

TC_LANG="es"
TC_VERSION="1.0.0"
TC_INSTALL_DATE=""
TC_GH_REPO="Davidgelves/TunnelCore"
TC_GH_BRANCH="main"
EOF
        # Registrar fecha de instalación
        sed -i "s/TC_INSTALL_DATE=\"\"/TC_INSTALL_DATE=\"$(date '+%Y-%m-%d')\"/" "$TC_CONF_FILE"
        chmod 644 "$TC_CONF_FILE"
    fi
}

# ── Leer un valor de la configuración ─────────────────────────
tc_config_get() {
    local key="$1" default="${2:-}"
    if [[ -f "$TC_CONF_FILE" ]]; then
        local val
        val="$(grep -E "^${key}=" "$TC_CONF_FILE" 2>/dev/null | tail -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//')"
        echo "${val:-$default}"
    else
        echo "$default"
    fi
}

# ── Escribir un valor en la configuración ─────────────────────
tc_config_set() {
    local key="$1" value="$2"
    tc_config_init
    if grep -qE "^${key}=" "$TC_CONF_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$TC_CONF_FILE"
    else
        echo "${key}=\"${value}\"" >> "$TC_CONF_FILE"
    fi
}

# ── Cargar toda la configuración ──────────────────────────────
tc_config_load() {
    tc_config_init
    # Solo cargar variables que empiecen con TC_
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        key="$(echo "$key" | xargs)"
        [[ "$key" == TC_* ]] || continue
        value="$(echo "$value" | sed 's/^"//;s/"$//')"
        export "$key=$value" 2>/dev/null || true
    done < "$TC_CONF_FILE"
}

# ── Mostrar configuración actual ──────────────────────────────
tc_config_show() {
    if [[ -f "$TC_CONF_FILE" ]]; then
        grep -vE '^#|^$' "$TC_CONF_FILE" | while IFS='=' read -r key value; do
            value="$(echo "$value" | sed 's/^"//;s/"$//')"
            printf '%b%-20s%b = %b%s%b\n' "$TC_DARK_GREEN" "$key" "$TC_NC" "$TC_WHITE" "$value" "$TC_NC"
        done
    else
        tc_msg_warn "No existe archivo de configuración."
    fi
}
