#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/vps.sh
#  Configuración y Mantenimiento del VPS
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════

tc_vps_change_root_pass() {
    tc_clear
    tc_title "CAMBIAR CONTRASEÑA DE ROOT"

    local p1 p2
    printf '%bIngrese nueva contraseña de root:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r -s p1
    echo ""
    printf '%bConfirme la contraseña:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r -s p2
    echo ""

    if [[ -z "$p1" || "$p1" != "$p2" ]]; then
        tc_msg_err "Las contraseñas no coinciden o están vacías."
        tc_pause
        return
    fi

    echo "root:${p1}" | chpasswd >/dev/null 2>&1
    tc_msg_ok "Contraseña de root cambiada correctamente."
    tc_pause
}

tc_vps_create_swap() {
    tc_clear
    tc_title "CONFIGURAR MEMORIA SWAP"

    local cur_swap
    cur_swap="$(free -h | awk '/^Swap:/ {print $2}')"
    printf '%bSWAP actual:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$cur_swap" "$TC_NC"
    tc_line

    local size_gb
    printf '%bTamaño de SWAP a crear en GB (ej: 1, 2, 4):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r size_gb

    if [[ ! "$size_gb" =~ ^[1-8]$ ]]; then
        tc_msg_err "Tamaño inválido (1 a 8 GB permitidos)."
        tc_pause
        return
    fi

    tc_msg_ok "Creando archivo SWAP de ${size_gb}GB..."
    swapoff -a 2>/dev/null || true
    rm -f /swapfile

    fallocate -l "${size_gb}G" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=$(( size_gb * 1024 )) status=progress
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1
    swapon /swapfile >/dev/null 2>&1

    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    tc_msg_ok "SWAP de ${size_gb}GB activado permanentemente."
    tc_pause
}

tc_vps_clean_cache() {
    tc_msg_ok "Limpiando memoria RAM y caché del sistema..."
    sync
    echo 3 > /proc/sys/vm/drop_caches
    tc_msg_ok "Caché de memoria liberado."
    tc_pause
}

tc_vps_set_timezone() {
    tc_clear
    tc_title "CAMBIAR ZONA HORARIA"
    printf '%bZona horaria actual:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$(timedatectl 2>/dev/null | grep 'Time zone' | awk '{print $3}' || date +%Z)" "$TC_NC"
    tc_line
    tc_opt "1" "América/Bogotá"
    tc_opt "2" "América/Lima"
    tc_opt "3" "América/Mexico_City"
    tc_opt "4" "América/Buenos_Aires"
    tc_opt "5" "América/Santiago"
    tc_opt "6" "América/Sao_Paulo"
    tc_opt "7" "América/Caracas"
    tc_opt "8" "Europa/Madrid"
    tc_line
    tc_opt "0" "VOLVER"
    tc_line
    tc_prompt "Opción"
    read -r tz_opt

    local tz=""
    case "$tz_opt" in
        1) tz="America/Bogota" ;;
        2) tz="America/Lima" ;;
        3) tz="America/Mexico_City" ;;
        4) tz="America/Argentina/Buenos_Aires" ;;
        5) tz="America/Santiago" ;;
        6) tz="America/Sao_Paulo" ;;
        7) tz="America/Caracas" ;;
        8) tz="Europe/Madrid" ;;
        0) return ;;
        *) tc_msg_err "Opción no válida."; tc_pause; return ;;
    esac

    timedatectl set-timezone "$tz" >/dev/null 2>&1 || {
        ln -sf "/usr/share/zoneinfo/${tz}" /etc/localtime
    }
    tc_msg_ok "Zona horaria actualizada a $tz."
    tc_pause
}

tc_vps_menu() {
    while true; do
        tc_clear
        tc_title "CONFIGURACION DE LA VPS"
        tc_opt "1" "CAMBIAR CONTRASEÑA DE ROOT"
        tc_opt "2" "CONFIGURAR MEMORIA SWAP"
        tc_opt "3" "LIMPIAR MEMORIA RAM / CACHÉ"
        tc_opt "4" "CAMBIAR ZONA HORARIA"
        tc_line
        tc_opt "0" "VOLVER"
        tc_line
        tc_prompt
        read -r opt

        case "$opt" in
            1|01) tc_vps_change_root_pass ;;
            2|02) tc_vps_create_swap ;;
            3|03) tc_vps_clean_cache ;;
            4|04) tc_vps_set_timezone ;;
            0|00) break ;;
            *) tc_msg_err "Opción no válida."; sleep 1 ;;
        esac
    done
}

