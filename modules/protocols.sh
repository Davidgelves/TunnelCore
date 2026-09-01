#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols.sh
#  Submenú Maestro de Protocolos de Conexión
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════

TC_PROTO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/protocols"

# ── Cargar submódulos de protocolos ───────────────────────────
[[ -f "${TC_PROTO_DIR}/v2ray.sh" ]] && source "${TC_PROTO_DIR}/v2ray.sh"
[[ -f "${TC_PROTO_DIR}/slowdns.sh" ]] && source "${TC_PROTO_DIR}/slowdns.sh"
[[ -f "${TC_PROTO_DIR}/hysteria.sh" ]] && source "${TC_PROTO_DIR}/hysteria.sh"
[[ -f "${TC_PROTO_DIR}/proxy.sh" ]] && source "${TC_PROTO_DIR}/proxy.sh"
[[ -f "${TC_PROTO_DIR}/dropbear.sh" ]] && source "${TC_PROTO_DIR}/dropbear.sh"
[[ -f "${TC_PROTO_DIR}/stunnel.sh" ]] && source "${TC_PROTO_DIR}/stunnel.sh"
[[ -f "${TC_PROTO_DIR}/badvpn.sh" ]] && source "${TC_PROTO_DIR}/badvpn.sh"
[[ -f "${TC_PROTO_DIR}/bhttp.sh" ]] && source "${TC_PROTO_DIR}/bhttp.sh"

tc_proto_status_opt() {
    local n="${1#0}" label="$2" status="$3" width=30
    [[ -z "$n" ]] && n="0"
    [[ -z "$status" ]] && status="x"
    printf '%b[%s]%b %b>%b %b%-*s%b %b%s%b\n' \
        "$TC_NEON" "$n" "$TC_NC" \
        "$TC_WHITE" "$TC_NC" \
        "$TC_WHITE" "$width" "$label" "$TC_NC" \
        "$TC_WHITE" "$status" "$TC_NC"
}

tc_proto_proxy_ports() {
    declare -f tc_proxy_is_running >/dev/null && tc_proxy_is_running || return 0
    declare -f tc_proxy_load_conf >/dev/null || return 0
    tc_proxy_load_conf >/dev/null 2>&1 || true
    [[ -n "${PROXY_PORT:-}" ]] && printf '%s' "$PROXY_PORT"
    [[ -n "${PROXY_PORT2:-}" ]] && printf ', %s' "$PROXY_PORT2"
}

tc_proto_ssh_ports() {
    local ports
    ports="$(grep -hE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -n -u)"
    [[ -z "$ports" ]] && ports="22"
    while read -r port; do
        [[ -z "$port" ]] && continue
        if tc_port_in_use "$port"; then
            printf '%s\n' "$port"
        fi
    done <<< "$ports" | awk 'BEGIN{sep=""} {printf "%s%s", sep, $0; sep=", "}'
}

tc_proto_stunnel_ports() {
    declare -f tc_stunnel_is_running >/dev/null && tc_stunnel_is_running || return 0
    [[ -f /etc/stunnel/stunnel.conf ]] || return 0
    awk -F= '/^[[:space:]]*accept[[:space:]]*=/{gsub(/[ \t]/,"",$2); if($2!="") print $2}' /etc/stunnel/stunnel.conf 2>/dev/null | sort -n -u | awk 'BEGIN{sep=""} {printf "%s%s", sep, $0; sep=", "}'
}

tc_proto_dropbear_ports() {
    declare -f tc_dropbear_is_running >/dev/null && tc_dropbear_is_running || return 0
    declare -f tc_dropbear_get_port >/dev/null && tc_dropbear_get_port
}

tc_proto_slowdns_ports() {
    declare -f tc_slow_is_running >/dev/null && tc_slow_is_running || return 0
    declare -f tc_slow_load_conf >/dev/null || return 0
    tc_slow_load_conf >/dev/null 2>&1 || true
    [[ -n "${SLOW_PORT:-}" ]] && printf '%s' "$SLOW_PORT"
    [[ -n "${SLOW_REDIRECT:-}" ]] && printf ', %s' "$SLOW_REDIRECT"
}

tc_proto_hysteria_ports() {
    declare -f tc_hyst_is_running >/dev/null && tc_hyst_is_running || return 0
    declare -f tc_hyst_load_conf >/dev/null || return 0
    tc_hyst_load_conf >/dev/null 2>&1 || true
    [[ -n "${HYST_PORT:-}" ]] && printf '%s' "$HYST_PORT"
}

tc_proto_badvpn_ports() {
    declare -f tc_badvpn_is_running >/dev/null && tc_badvpn_is_running || return 0
    declare -f tc_badvpn_load_conf >/dev/null || return 0
    tc_badvpn_load_conf >/dev/null 2>&1 || true
    [[ -n "${BADVPN_PORT:-}" ]] && printf '%s' "$BADVPN_PORT"
}

tc_proto_bhttp_ports_one() {
    local proto="$1" out=""
    declare -f tc_bhttp_load_conf >/dev/null || return 0
    declare -f tc_bhttp_is_running >/dev/null && tc_bhttp_is_running "$proto" || return 0
    tc_bhttp_load_conf "$proto" >/dev/null 2>&1 || true
    if [[ "${BHTTP_TLS:-0}" = "1" && -n "${BHTTP_TLS_PORT:-}" ]]; then
        out="${BHTTP_TLS_PORT}/tls"
    else
        out="${BHTTP_PORT:-8080}"
    fi
    [[ -n "${BHTTP_EXTRA_PORTS:-}" ]] && out="${out}, ${BHTTP_EXTRA_PORTS}"
    printf '%s' "$out"
}

tc_proto_v2ray_ports() {
    local core_filter="$1" db="/etc/SSHPlus/v2ray/configs.db"
    [[ -s "$db" ]] || return 0
    awk -F'|' -v core_filter="$core_filter" '
        $1 ~ /^[0-9]+$/ {
            core=tolower($10)
            if (core == "") core="v2ray"
            if (core != core_filter) next
            print $1
        }
    ' "$db" 2>/dev/null | sort -n -u | awk 'BEGIN{sep=""} {printf "%s%s", sep, $0; sep=", "}'
}

tc_protocols_ports_overview() {
    local entries=() value i item label ports text sep line_len text_len max_width=58

    value="$(tc_proto_ssh_ports)"; [[ -n "$value" ]] && entries+=("SSH|${value}")
    value="$(tc_proto_proxy_ports)"; [[ -n "$value" ]] && entries+=("PROXY|${value}")
    value="$(tc_proto_stunnel_ports)"; [[ -n "$value" ]] && entries+=("STUNNEL|${value}")
    value="$(tc_proto_dropbear_ports)"; [[ -n "$value" ]] && entries+=("DROPBEAR|${value}")
    value="$(tc_proto_slowdns_ports)"; [[ -n "$value" ]] && entries+=("SLOWDNS|${value}")
    value="$(tc_proto_hysteria_ports)"; [[ -n "$value" ]] && entries+=("HYSTERIA|${value}")
    value="$(tc_proto_v2ray_ports v2ray)"; [[ -n "$value" ]] && entries+=("V2RAY|${value}")
    value="$(tc_proto_v2ray_ports xray)"; [[ -n "$value" ]] && entries+=("XRAY|${value}")
    value="$(tc_proto_badvpn_ports)"; [[ -n "$value" ]] && entries+=("BADVPN|${value}")
    value="$(tc_proto_bhttp_ports_one btun)"; [[ -n "$value" ]] && entries+=("BTUN|${value}")
    value="$(tc_proto_bhttp_ports_one hcr)"; [[ -n "$value" ]] && entries+=("HCR|${value}")

    [[ ${#entries[@]} -eq 0 ]] && return 0

    tc_line
    printf '%bPUERTOS ACTIVOS%b\n' "$TC_YELLOW" "$TC_NC"
    tc_line
    line_len=0
    for i in "${!entries[@]}"; do
        item="${entries[$i]}"
        label="${item%%|*}"
        ports="${item#*|}"
        text="${label}:${ports}"
        text_len="${#text}"
        sep=""
        if (( line_len > 0 )); then
            if (( line_len + 4 + text_len > max_width )); then
                printf '\n'
                line_len=0
            else
                sep="    "
                line_len=$((line_len + 4))
            fi
        fi
        printf '%s%b%s:%b%b%s%b' "$sep" "$TC_YELLOW" "$label" "$TC_NC" "$TC_WHITE" "$ports" "$TC_NC"
        line_len=$((line_len + text_len))
    done
    printf '\n'
    tc_line
}

tc_protocols_menu() {
    while true; do
        tc_clear
        tc_title "CONFIGURACION DE PROTOCOLOS"
        tc_protocols_ports_overview

        tc_proto_status_opt "1" "PROXY HTTP/SOCKS"     "$(tc_proxy_status_mark 2>/dev/null || echo 'x')"
        tc_proto_status_opt "2" "STUNNEL (SSL TUNNEL)" "$(tc_stunnel_status_mark 2>/dev/null || echo 'x')"
        tc_proto_status_opt "3" "DROPBEAR SSH"         "$(tc_dropbear_status_mark 2>/dev/null || echo 'x')"
        tc_proto_status_opt "4" "SLOWDNS (DNSTT)"      "$(tc_slow_status_mark 2>/dev/null || echo 'x')"
        tc_proto_status_opt "5" "HYSTERIA v1 (UDP)"    "$(tc_hyst_status_mark 2>/dev/null || echo 'x')"
        tc_proto_status_opt "6" "V2RAY / XRAY"         "$(tc_xray_status_mark 2>/dev/null || echo 'x')"
        tc_proto_status_opt "7" "BADVPN (UDPGW)"       "$(tc_badvpn_status_mark 2>/dev/null || echo 'x')"
        tc_proto_status_opt "8" "BTUN / HCR"           "$(tc_bhttp_status_summary 2>/dev/null || echo 'x/x')"
        tc_line
        tc_opt "0" "$(_t 'back')"
        tc_line

        tc_prompt
        read -r p_opt

        case "$p_opt" in
            1|01) declare -f tc_proxy_menu >/dev/null && tc_proxy_menu ;;
            2|02) declare -f tc_stunnel_menu >/dev/null && tc_stunnel_menu ;;
            3|03) declare -f tc_dropbear_menu >/dev/null && tc_dropbear_menu ;;
            4|04) declare -f tc_slow_menu >/dev/null && tc_slow_menu ;;
            5|05) declare -f tc_hyst_menu >/dev/null && tc_hyst_menu ;;
            6|06) declare -f tc_xray_menu >/dev/null && tc_xray_menu ;;
            7|07) declare -f tc_badvpn_menu >/dev/null && tc_badvpn_menu ;;
            8|08) declare -f tc_bhttp_menu >/dev/null && tc_bhttp_menu ;;
            0|00) break ;;
            *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
        esac
    done
}
