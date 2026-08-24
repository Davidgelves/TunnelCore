#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/network.sh
#  Optimización de Red, TCP BBR, Firewall y Seguridad
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

tc_bbr_is_active() {
    sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"
}

tc_bbr_enable() {
    tc_msg_ok "Activando algoritmo TCP BBR..."
    local sysctl_conf="/etc/sysctl.d/99-tunnelcore-bbr.conf"

    cat > "$sysctl_conf" <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    sysctl -p "$sysctl_conf" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true

    if tc_bbr_is_active; then
        tc_msg_ok "TCP BBR activado con éxito."
    else
        tc_msg_warn "BBR no se pudo activar (requiere Kernel Linux 4.9+)."
    fi
    tc_pause
}

tc_network_optimize() {
    tc_msg_ok "Aplicando optimizaciones de Kernel y red seguras..."
    local iface
    iface="$(tc_detect_interface)"

    local sysctl_opt="/etc/sysctl.d/99-tunnelcore-net.conf"
    cat > "$sysctl_opt" <<EOF
# TunnelCore Network Tuning
net.ipv4.ip_forward = 1
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 16384
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 20
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_tw_reuse = 1
fs.file-max = 1000000
EOF

    sysctl -p "$sysctl_opt" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true

    # TCP MSS Clamping para túneles y SlowDNS
    iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 || \
        iptables -t mangle -I FORWARD 1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 || true

    tc_msg_ok "Optimizaciones de red aplicadas correctamente (Interfaz: $iface)."
    tc_pause
}

tc_block_torrents() {
    tc_msg_ok "Bloqueando puertos comunes de Torrent y P2P..."
    iptables -A FORWARD -m string --algo bm --string "BitTorrent" -j DROP >/dev/null 2>&1 || true
    iptables -A FORWARD -m string --algo bm --string "peer_id=" -j DROP >/dev/null 2>&1 || true
    iptables -A FORWARD -m string --algo bm --string ".torrent" -j DROP >/dev/null 2>&1 || true
    iptables -A FORWARD -m string --algo bm --string "announce.php?passkey=" -j DROP >/dev/null 2>&1 || true
    tc_msg_ok "Filtros P2P / Torrent aplicados."
    tc_pause
}

tc_network_menu() {
    while true; do
        tc_clear
        tc_title "RED Y SEGURIDAD"

        local bbr_st="${TC_RED}[DESACTIVADO]${TC_NC}"
        tc_bbr_is_active && bbr_st="${TC_GREEN}[ACTIVADO]${TC_NC}"

        printf '%bESTADO TCP BBR:%b %b\n' "$TC_DARK_GREEN" "$TC_NC" "$bbr_st"
        tc_line
        tc_opt "1" "ACTIVAR TCP BBR (Mayor velocidad / menor latencia)"
        tc_opt "2" "APLICAR OPTIMIZACIONES DE KERNEL / BUFFER TCP"
        tc_opt "3" "BLOQUEAR TRAFICO P2P / TORRENTS"
        tc_line
        tc_opt "0" "VOLVER"
        tc_line
        tc_prompt
        read -r opt

        case "$opt" in
            1|01) tc_bbr_enable ;;
            2|02) tc_network_optimize ;;
            3|03) tc_block_torrents ;;
            0|00) break ;;
            *) tc_msg_err "Opción no válida."; sleep 1 ;;
        esac
    done
}

