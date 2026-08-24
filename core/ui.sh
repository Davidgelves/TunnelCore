#!/bin/bash
# TunnelCore — core/ui.sh
# Librería visual compartida: colores, líneas, menú, prompts.
# Todas las funciones usan el prefijo tc_ para evitar colisiones.

# ── Colores ANSI ───────────────────────────────────────────────
TC_NC=$'\033[0m'
TC_RED=$'\033[1;31m'
TC_GREEN=$'\033[1;32m'
TC_YELLOW=$'\033[1;33m'
TC_BLUE=$'\033[1;34m'
TC_WHITE=$'\033[1;37m'
TC_CYAN=$'\033[1;38;2;76;228;255m'
TC_NEON=$'\033[1;38;2;0;255;127m'
TC_DARK_GREEN=$'\033[0;32m'
TC_PALE_GOLD=$'\033[1;38;2;240;230;140m'

# ── Dimensiones de terminal ────────────────────────────────────
TC_IW=60  # ancho interno del menú

tc_resize() {
    local cols
    cols="$(tput cols 2>/dev/null || echo 80)"
    [[ ! "$cols" =~ ^[0-9]+$ ]] && cols=80
    TC_IW=60
    [[ "$cols" -lt 62 ]] && TC_IW=$(( cols - 2 ))
    [[ "$TC_IW" -lt 42 ]] && TC_IW=42
}

# ── Limpiar pantalla ───────────────────────────────────────────
tc_clear() {
    printf '\033c\033[3J\033[H\033[2J'
    tc_resize
}

# ── Línea separadora ──────────────────────────────────────────
tc_line() {
    local i
    tc_resize
    printf '%b' "$TC_CYAN"
    for ((i = 0; i < TC_IW; i++)); do printf '='; done
    printf '%b\n' "$TC_NC"
}

# ── Título centrado ───────────────────────────────────────────
tc_title() {
    local title="$1" pad
    tc_resize
    tc_line
    pad=$(( (TC_IW - ${#title}) / 2 ))
    [[ "$pad" -lt 0 ]] && pad=0
    printf '%*s%b%s%b\n' "$pad" "" "$TC_CYAN" "$title" "$TC_NC"
    tc_line
}

# ── Opción de menú [N] > Texto  estado ────────────────────────
tc_opt() {
    local n="${1#0}"
    [[ -z "$n" ]] && n="0"
    printf '%b[%s]%b %b>%b %b%s%b %b\n' \
        "$TC_NEON" "$n" "$TC_NC" \
        "$TC_WHITE" "$TC_NC" \
        "$TC_WHITE" "$2" "$TC_NC" \
        "${3:-}"
}

# ── Par de opciones en la misma línea ─────────────────────────
tc_opt_pair() {
    local n1="${1#0}" t1="$2" s1="${3:-}" n2="${4#0}" t2="$5" s2="${6:-}"
    [[ -z "$n1" ]] && n1="0"
    [[ -z "$n2" ]] && n2="0"
    printf '%b[%s]%b %b>%b %-18s%b  %b[%s]%b %b>%b %s%b\n' \
        "$TC_NEON" "$n1" "$TC_NC" "$TC_WHITE" "$TC_NC" "$t1" "$s1" \
        "$TC_NEON" "$n2" "$TC_NC" "$TC_WHITE" "$TC_NC" "$t2" "$s2"
}

# ── Info del header: etiqueta + valor ─────────────────────────
tc_info() {
    printf '%b%s:%b %b%s%b' "$TC_DARK_GREEN" "$1" "$TC_NC" "$TC_WHITE" "$2" "$TC_NC"
}

# ── Info en 3 columnas (para el header del menú) ──────────────
tc_info_row() {
    # Uso: tc_info_row "Label1" "Val1" "Label2" "Val2" "Label3" "Val3"
    local col_w=$(( TC_IW / 3 ))
    local c1 c2 c3
    printf -v c1 '%s: %s' "$1" "$2"
    printf -v c2 '%s: %s' "$3" "$4"
    printf -v c3 '%s: %s' "$5" "$6"
    printf '%b%-*s%b%b%-*s%b%b%-*s%b\n' \
        "$TC_WHITE" "$col_w" "$c1" "$TC_NC" \
        "$TC_WHITE" "$col_w" "$c2" "$TC_NC" \
        "$TC_WHITE" "$col_w" "$c3" "$TC_NC"
}

# ── Prompt de opción ──────────────────────────────────────────
tc_prompt() {
    local label="${1:-}"
    if [[ -z "$label" ]]; then
        if declare -f _t >/dev/null; then
            label="$(_t 'option')"
        else
            label="Opcion"
        fi
    fi
    printf '%b%s:%b ' "$TC_CYAN" "$label" "$TC_NC"
}

# ── Pausa (Enter para continuar) ──────────────────────────────
tc_pause() {
    local msg=""
    if declare -f _t >/dev/null; then
        msg="$(_t 'press_enter')"
    else
        msg="Enter para continuar"
    fi
    printf '\n%b* %b%s%b' "$TC_YELLOW" "$TC_WHITE" "$msg" "$TC_NC"
    read -r _
}

# ── Confirmación s/n ──────────────────────────────────────────
# Uso: if tc_confirm "¿Continuar?"; then ...; fi
tc_confirm() {
    local msg="${1:-}"
    if [[ -z "$msg" ]]; then
        if declare -f _t >/dev/null; then
            msg="$(_t 'confirm')"
        else
            msg="Confirmar"
        fi
    fi
    printf '%b%s %b[s/n]:%b ' "$TC_GREEN" "$msg" "$TC_YELLOW" "$TC_NC"
    read -r resp
    [[ "$resp" =~ ^[sS]$ ]]
}

# ── Mensaje de estado ─────────────────────────────────────────
tc_msg_ok()   { printf '%b[✓]%b %s\n' "$TC_GREEN"  "$TC_NC" "$1"; }
tc_msg_warn() { printf '%b[!]%b %s\n' "$TC_YELLOW" "$TC_NC" "$1"; }
tc_msg_err()  { printf '%b[✗]%b %s\n' "$TC_RED"    "$TC_NC" "$1"; }

# ── Marca de estado ON/OFF ────────────────────────────────────
tc_status_mark() {
    # Uso: tc_status_mark "servicio" → imprime "o" verde o "x" rojo
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        printf '%bo%b' "$TC_GREEN" "$TC_NC"
    else
        printf '%bx%b' "$TC_RED" "$TC_NC"
    fi
}

# ── Spinner de progreso ───────────────────────────────────────
tc_spinner() {
    local pid=$1 msg="${2:-Procesando...}" chars='|/-\'
    local i=0
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r%b%s %c%b' "$TC_CYAN" "$msg" "${chars:i++%4:1}" "$TC_NC"
        sleep 0.15
    done
    printf '\r%b%s ✓%b\n' "$TC_GREEN" "$msg" "$TC_NC"
    tput cnorm 2>/dev/null || true
}

# Inicializar dimensiones al cargar
tc_resize
