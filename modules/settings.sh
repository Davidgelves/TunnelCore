#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/settings.sh
#  Ajustes del Script: Actualizaciones y Backup de Base de Datos
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════

tc_settings_update() {
    tc_clear
    tc_title "ACTUALIZAR TUNNELCORE"

    local repo_url tarball_url branch
    repo_url="$(tc_config_get "TC_REPO_URL" "https://gitlab.com/Davidgelves/tunnelcore.git")"
    tarball_url="$(tc_config_get "TC_TARBALL_URL" "https://gitlab.com/Davidgelves/tunnelcore/-/archive/main/tunnelcore-main.tar.gz")"
    branch="$(tc_config_get "TC_BRANCH" "main")"

    tc_msg_ok "Buscando actualizaciones en GitLab (${repo_url}@${branch})..."
    local install_dir="/opt/tunnelcore"

    if [[ -d "${install_dir}/.git" ]]; then
        (
            cd "$install_dir"
            git remote set-url origin "$repo_url" >/dev/null 2>&1 || true
            git fetch --all >/dev/null 2>&1
            git reset --hard "origin/${branch}" >/dev/null 2>&1
        )
        chmod -R +x "$install_dir" 2>/dev/null || true
        chmod 755 "${install_dir}/tunnelcore" 2>/dev/null || true
        tc_msg_ok "TunnelCore actualizado correctamente vía git."
    else
        # Si no fue clonado con git, descargar tarball
        local tmp_tar="/tmp/tunnelcore-update.tar.gz"
        local url="$tarball_url"

        if tc_download "$url" "$tmp_tar" 3; then
            mkdir -p "$install_dir"
            tar -xzf "$tmp_tar" -C /tmp
            cp -rf "/tmp/tunnelcore-${branch}/"* "$install_dir/" 2>/dev/null || cp -rf "/tmp/tunnelcore-"*/* "$install_dir/" 2>/dev/null || true
            rm -rf "$tmp_tar" "/tmp/tunnelcore-"*
            chmod -R +x "$install_dir" 2>/dev/null || true
            chmod 755 "${install_dir}/tunnelcore" 2>/dev/null || true
            tc_msg_ok "TunnelCore actualizado correctamente."
        else
            tc_msg_err "No se pudo descargar la actualización."
        fi
    fi
    tc_pause
}

tc_settings_backup_users() {
    tc_clear
    tc_title "BACKUP DE USUARIOS"

    local bk_dir="/etc/tunnelcore/backups"
    mkdir -p "$bk_dir"
    local bk_file="${bk_dir}/users-backup-$(date '+%Y%m%d_%H%M%S').tar.gz"

    if [[ ! -d "/etc/tunnelcore" ]]; then
        tc_msg_warn "No hay datos que respaldar."
        tc_pause
        return
    fi

    tar -czf "$bk_file" -C /etc/tunnelcore users.db passwords 2>/dev/null || true

    if [[ -f "$bk_file" ]]; then
        tc_msg_ok "Backup creado con éxito:"
        printf '  %b%s%b\n' "$TC_GREEN" "$bk_file" "$TC_NC"
    else
        tc_msg_err "Error al crear el backup."
    fi
    tc_pause
}

tc_settings_restore_users() {
    tc_clear
    tc_title "RESTAURAR BACKUP DE USUARIOS"

    local bk_dir="/etc/tunnelcore/backups"
    if [[ ! -d "$bk_dir" ]] || [[ -z "$(ls -A "$bk_dir" 2>/dev/null)" ]]; then
        tc_msg_warn "No se encontraron copias de seguridad en $bk_dir."
        tc_pause
        return
    fi

    local -a bk_list=()
    while IFS= read -r f; do
        [[ -n "$f" ]] && bk_list+=("$f")
    done < <(ls -1t "$bk_dir"/*.tar.gz 2>/dev/null)

    for i in "${!bk_list[@]}"; do
        tc_opt "$((i + 1))" "$(basename "${bk_list[$i]}")"
    done
    tc_line
    tc_opt "0" "CANCELAR"
    tc_line

    local sel
    tc_prompt "Seleccione backup a restaurar"
    read -r sel
    [[ "$sel" == "0" ]] && return
    if [[ ! "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#bk_list[@]} )); then
        tc_msg_err "Opción no válida."
        tc_pause
        return
    fi

    local target_bk="${bk_list[$((sel - 1))]}"
    if tc_confirm "¿Restaurar '${target_bk}'? Esto sobreescribirá los usuarios actuales."; then
        tar -xzf "$target_bk" -C /etc/tunnelcore/
        tc_msg_ok "Usuarios restaurados con éxito."
    fi
    tc_pause
}

tc_settings_uninstall_script() {
    tc_clear
    tc_title "$(_t 'settings_uninstall')"
    tc_msg_warn "$(_t 'settings_uninstall_warn')"
    tc_line

    if ! tc_confirm "$(_t 'settings_uninstall_confirm')"; then
        tc_msg_warn "$(_t 'cancel')"
        tc_pause
        return
    fi

    local user user_file managed_users
    managed_users="$(mktemp)"
    {
        if [[ -f /etc/tunnelcore/users.db ]]; then
            while IFS='|' read -r user _; do
                [[ -z "$user" ]] && continue
                printf '%s\n' "$user"
            done < /etc/tunnelcore/users.db
        fi
        for user_file in /etc/tunnelcore/passwords/* /etc/SSHPlus/senha/*; do
            [[ -f "$user_file" ]] || continue
            printf '%s\n' "${user_file##*/}"
        done
    } | awk 'NF && $0 !~ /[^A-Za-z0-9._-]/ {print}' | sort -u > "$managed_users"

    while read -r user; do
        [[ -z "$user" ]] && continue
        id "$user" >/dev/null 2>&1 && userdel -r "$user" >/dev/null 2>&1 || userdel -f "$user" >/dev/null 2>&1 || true
    done < "$managed_users"
    rm -f "$managed_users"

    systemctl stop \
        tunnelcore-proxy tunnelcore-proxy2 tunnelcore-ws tunnelcore-limiter \
        checkuser tunnelcore-checkuser tunnelcore-badvpn slowdns hysteria-server \
        tunnelcore-btun tunnelcore-hcr \
        xray v2ray dropbear squid squid3 stunnel4 stunnel >/dev/null 2>&1 || true
    systemctl disable \
        tunnelcore-proxy tunnelcore-proxy2 tunnelcore-ws tunnelcore-limiter \
        checkuser tunnelcore-checkuser tunnelcore-badvpn slowdns hysteria-server \
        tunnelcore-btun tunnelcore-hcr \
        xray v2ray dropbear squid squid3 stunnel4 stunnel >/dev/null 2>&1 || true

    local unit
    for unit in $(systemctl list-units 'v2ray@*.service' 'xray@*.service' --all --no-legend 2>/dev/null | awk '{print $1}'); do
        systemctl disable --now "$unit" >/dev/null 2>&1 || true
    done
    for unit in $(systemctl list-unit-files 'v2ray@*.service' 'xray@*.service' --no-legend 2>/dev/null | awk '{print $1}'); do
        systemctl disable --now "$unit" >/dev/null 2>&1 || true
    done
    for unit in $(systemctl list-units 'tunnelcore-btun-*.service' 'tunnelcore-hcr-*.service' --all --no-legend 2>/dev/null | awk '{print $1}'); do
        systemctl disable --now "$unit" >/dev/null 2>&1 || true
    done
    for unit in $(systemctl list-unit-files 'tunnelcore-btun-*.service' 'tunnelcore-hcr-*.service' --no-legend 2>/dev/null | awk '{print $1}'); do
        systemctl disable --now "$unit" >/dev/null 2>&1 || true
    done

    rm -f \
        /etc/systemd/system/tunnelcore-proxy.service \
        /etc/systemd/system/tunnelcore-proxy2.service \
        /etc/systemd/system/tunnelcore-ws.service \
        /etc/systemd/system/tunnelcore-limiter.service \
        /etc/systemd/system/checkuser.service \
        /etc/systemd/system/tunnelcore-checkuser.service \
        /etc/systemd/system/tunnelcore-badvpn.service \
        /etc/systemd/system/tunnelcore-btun.service \
        /etc/systemd/system/tunnelcore-hcr.service \
        /etc/systemd/system/tunnelcore-btun-*.service \
        /etc/systemd/system/tunnelcore-hcr-*.service \
        /etc/systemd/system/slowdns.service \
        /etc/systemd/system/hysteria-server.service \
        /etc/systemd/system/xray.service \
        /etc/systemd/system/v2ray.service \
        /etc/systemd/system/xray@.service \
        /etc/systemd/system/v2ray@.service >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed >/dev/null 2>&1 || true

    rm -f \
        /usr/local/bin/tunnelcore /usr/bin/tunnelcore /bin/tunnelcore \
        /usr/local/bin/menu /usr/bin/menu /bin/menu \
        /usr/local/bin/tunnelcore-limiter \
        /usr/local/bin/badvpn-udpgw \
        /usr/local/bin/dnstt-server \
        /usr/local/bin/hysteria1 \
        /usr/local/lib/tunnelcore-bilola-server \
        /usr/local/lib/tunnelcore-hcr-server \
        /usr/local/bin/xray /usr/bin/xray /bin/xray \
        /usr/local/bin/v2ray /usr/bin/v2ray /bin/v2ray >/dev/null 2>&1 || true

    rm -f /etc/profile.d/tunnelcore.sh >/dev/null 2>&1 || true
    sed -i "/alias menu='tunnelcore'/d" /root/.bashrc 2>/dev/null || true
    sed -i "\|. /etc/profile.d/tunnelcore.sh|d" /root/.bashrc 2>/dev/null || true
    sed -i "\|^Banner /etc/tunnelcore/banner|d" /etc/ssh/sshd_config 2>/dev/null || true
    sed -i 's|^DROPBEAR_BANNER="/etc/tunnelcore/banner"|#DROPBEAR_BANNER=""|' /etc/default/dropbear 2>/dev/null || true

    if command -v apt-get >/dev/null 2>&1; then
        apt-get purge -y dropbear squid squid3 stunnel4 >/dev/null 2>&1 || true
        apt-get autoremove -y >/dev/null 2>&1 || true
    fi

    rm -rf \
        /opt/tunnelcore \
        /etc/tunnelcore \
        /etc/SSHPlus \
        /root/TunnelCore \
        /usr/local/etc/xray \
        /usr/local/etc/v2ray \
        /etc/xray \
        /etc/v2ray \
        /var/log/xray >/dev/null 2>&1 || true

    tc_msg_ok "$(_t 'settings_uninstall_done')"
    sleep 2
    clear
    exit 0
}

tc_settings_menu() {
    while true; do
        tc_clear
        tc_title "$(_t 'settings_title')"
        tc_opt "1" "$(_t 'settings_update')"
        tc_opt "2" "$(_t 'settings_backup')"
        tc_opt "3" "$(_t 'settings_restore')"
        tc_opt "4" "$(_t 'settings_view')"
        tc_opt "5" "$(_t 'settings_lang')"
        tc_opt "6" "$(_t 'settings_uninstall')"
        tc_line
        tc_opt "0" "$(_t 'back')"
        tc_line
        tc_prompt
        read -r opt

        case "$opt" in
            1|01) tc_settings_update ;;
            2|02) tc_settings_backup_users ;;
            3|03) tc_settings_restore_users ;;
            4|04)
                tc_clear
                tc_title "$(_t 'settings_view')"
                tc_config_show
                tc_line
                tc_pause
                ;;
            5|05)
                if declare -f tc_lang_select >/dev/null; then
                    tc_lang_select
                fi
                ;;
            6|06) tc_settings_uninstall_script ;;
            0|00) break ;;
            *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
        esac
    done
}
