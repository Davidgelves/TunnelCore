#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols.sh
#  Submenú Maestro de Protocolos de Conexión
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_PROTO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/protocols"

# ── Cargar submódulos de protocolos ───────────────────────────
[[ -f "${TC_PROTO_DIR}/v2ray.sh" ]] && source "${TC_PROTO_DIR}/v2ray.sh"
[[ -f "${TC_PROTO_DIR}/slowdns.sh" ]] && source "${TC_PROTO_DIR}/slowdns.sh"
[[ -f "${TC_PROTO_DIR}/hysteria.sh" ]] && source "${TC_PROTO_DIR}/hysteria.sh"
[[ -f "${TC_PROTO_DIR}/proxy.sh" ]] && source "${TC_PROTO_DIR}/proxy.sh"
[[ -f "${TC_PROTO_DIR}/dropbear.sh" ]] && source "${TC_PROTO_DIR}/dropbear.sh"
[[ -f "${TC_PROTO_DIR}/stunnel.sh" ]] && source "${TC_PROTO_DIR}/stunnel.sh"
[[ -f "${TC_PROTO_DIR}/badvpn.sh" ]] && source "${TC_PROTO_DIR}/badvpn.sh"

tc_protocols_menu() {
    while true; do
        tc_clear
        tc_title "CONFIGURACION DE PROTOCOLOS"

        tc_opt "1" "V2RAY / XRAY"                      "  $(tc_xray_status_mark 2>/dev/null || echo '')"
        tc_opt "2" "SLOWDNS (DNSTT)"                   "  $(tc_slow_status_mark 2>/dev/null || echo '')"
        tc_opt "3" "HYSTERIA v1 UDP"                   "  $(tc_hyst_status_mark 2>/dev/null || echo '')"
        tc_opt "4" "PROXY HTTP / SOCKS (PAYLOAD / WS)" "  $(tc_proxy_status_mark 2>/dev/null || echo '')"
        tc_opt "5" "DROPBEAR SSH"                      "  $(tc_dropbear_status_mark 2>/dev/null || echo '')"
        tc_opt "6" "STUNNEL (SSL TUNNEL)"              "  $(tc_stunnel_status_mark 2>/dev/null || echo '')"
        tc_opt "7" "BADVPN (UDPGW)"                    "  $(tc_badvpn_status_mark 2>/dev/null || echo '')"
        tc_line
        tc_opt "0" "$(_t 'back')"
        tc_line

        tc_prompt
        read -r p_opt

        case "$p_opt" in
            1|01) declare -f tc_xray_menu >/dev/null && tc_xray_menu ;;
            2|02) declare -f tc_slow_menu >/dev/null && tc_slow_menu ;;
            3|03) declare -f tc_hyst_menu >/dev/null && tc_hyst_menu ;;
            4|04) declare -f tc_proxy_menu >/dev/null && tc_proxy_menu ;;
            5|05) declare -f tc_dropbear_menu >/dev/null && tc_dropbear_menu ;;
            6|06) declare -f tc_stunnel_menu >/dev/null && tc_stunnel_menu ;;
            7|07) declare -f tc_badvpn_menu >/dev/null && tc_badvpn_menu ;;
            0|00) break ;;
            *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
        esac
    done
}
