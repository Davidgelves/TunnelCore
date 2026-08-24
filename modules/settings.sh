#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/settings.sh
#  Ajustes del Script: Actualizaciones y Backup de Base de Datos
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

tc_settings_update() {
    tc_clear
    tc_title "ACTUALIZAR TUNNELCORE"

    local repo branch
    repo="$(tc_config_get "TC_GH_REPO" "Davidgelves/TunnelCore")"
    branch="$(tc_config_get "TC_GH_BRANCH" "main")"

    tc_msg_ok "Buscando actualizaciones en GitHub (${repo}@${branch})..."
    local install_dir="/opt/tunnelcore"

    if [[ -d "${install_dir}/.git" ]]; then
        (
            cd "$install_dir"
            git fetch --all >/dev/null 2>&1
            git reset --hard "origin/${branch}" >/dev/null 2>&1
        )
        tc_msg_ok "TunnelCore actualizado correctamente vía git."
    else
        # Si no fue clonado con git, descargar tarball
        local tmp_tar="/tmp/tunnelcore-update.tar.gz"
        local url="https://github.com/${repo}/archive/refs/heads/${branch}.tar.gz"

        if tc_download "$url" "$tmp_tar" 3; then
            mkdir -p "$install_dir"
            tar -xzf "$tmp_tar" -C /tmp
            cp -rf "/tmp/TunnelCore-${branch}/"* "$install_dir/" 2>/dev/null || cp -rf "/tmp/TunnelCore-"*/* "$install_dir/" 2>/dev/null || true
            rm -rf "$tmp_tar" "/tmp/TunnelCore-"*
            chmod +x "${install_dir}/tunnelcore"
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

tc_settings_menu() {
    while true; do
        tc_clear
        tc_title "$(_t 'settings_title')"
        tc_opt "1" "$(_t 'settings_update')"
        tc_opt "2" "$(_t 'settings_backup')"
        tc_opt "3" "$(_t 'settings_restore')"
        tc_opt "4" "$(_t 'settings_view')"
        tc_opt "5" "$(_t 'settings_lang')"
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
            0|00) break ;;
            *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
        esac
    done
}

