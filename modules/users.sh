#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/users.sh
#  Gestión completa de usuarios SSH/VPN
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_USERS_DIR="/etc/tunnelcore"
TC_USERS_DB="${TC_USERS_DIR}/users.db"
TC_PASS_DIR="${TC_USERS_DIR}/passwords"

tc_users_init() {
    mkdir -p "$TC_USERS_DIR" "$TC_PASS_DIR"
    chmod 700 "$TC_PASS_DIR"
    [[ -f "$TC_USERS_DB" ]] || touch "$TC_USERS_DB"
    chmod 600 "$TC_USERS_DB"

    # Registrar shells válidos en /etc/shells para que Dropbear y PAM permitan autenticar
    grep -qxF "/bin/false" /etc/shells 2>/dev/null || echo "/bin/false" >> /etc/shells
    grep -qxF "/usr/sbin/nologin" /etc/shells 2>/dev/null || echo "/usr/sbin/nologin" >> /etc/shells
}

# ── Validar nombre de usuario ─────────────────────────────────
tc_valid_username() {
    local u="$1"
    [[ "$u" =~ ^[a-zA-Z0-9_-]{2,20}$ ]]
}

# ── Verificar si usuario existe ───────────────────────────────
tc_user_exists() {
    local u="$1"
    id "$u" >/dev/null 2>&1 || grep -qE "^[[:space:]]*${u}[[:space:]]*\|" "$TC_USERS_DB" 2>/dev/null
}

# ── Obtener conexiones activas de un usuario ──────────────────
tc_user_active_conns() {
    local u="$1"
    ps -u "$u" 2>/dev/null | grep -cE 'sshd|dropbear' || echo "0"
}

# ── 1. CREAR USUARIO ──────────────────────────────────────────
tc_user_create() {
    tc_users_init
    tc_clear
    tc_title "CREAR NUEVO USUARIO SSH/VPN"

    local username password days limit expiry_date

    # 1. Nombre de usuario
    while true; do
        printf '%bNombre de usuario (2-20 carácteres):%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r username
        username="$(echo "$username" | tr -d ' ')"
        if [[ -z "$username" ]]; then
            tc_msg_err "El nombre de usuario no puede estar vacío."
            continue
        elif ! tc_valid_username "$username"; then
            tc_msg_err "Solo se permiten letras, números, guiones (-) y (_, 2 a 20 carácteres)."
            continue
        elif tc_user_exists "$username"; then
            tc_msg_err "El usuario '$username' ya existe en el sistema."
            continue
        fi
        break
    done

    # 2. Contraseña
    while true; do
        printf '%bContraseña (Enter para generar aleatoria):%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r password
        if [[ -z "$password" ]]; then
            password="$(tc_rand_string 8)"
            printf '%bContraseña generada:%b %b%s%b\n' "$TC_YELLOW" "$TC_NC" "$TC_GREEN" "$password" "$TC_NC"
        fi
        break
    done

    # 3. Duración en días
    while true; do
        printf '%bDuración en días [1-365]:%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r days
        [[ -z "$days" ]] && days="30"
        if [[ ! "$days" =~ ^[0-9]+$ ]] || (( days < 1 || days > 365 )); then
            tc_msg_err "Ingrese un número válido de días (1 a 365)."
            continue
        fi
        break
    done

    expiry_date="$(date '+%Y-%m-%d' -d "+${days} days" 2>/dev/null || date -v "+${days}d" '+%Y-%m-%d')"

    # 4. Límite de conexiones
    while true; do
        printf '%bLímite de conexiones simultáneas [1-999] (Enter = 1):%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r limit
        [[ -z "$limit" ]] && limit="1"
        if [[ ! "$limit" =~ ^[0-9]+$ ]] || (( limit < 1 || limit > 999 )); then
            tc_msg_err "Ingrese un límite válido (1 a 999)."
            continue
        fi
        break
    done

    # 5. Crear usuario en el sistema Linux
    # Usar /bin/false o /usr/sbin/nologin si no existe shell específico
    local shell_bin="/bin/false"
    [[ -x "/bin/false" ]] || shell_bin="/usr/sbin/nologin"

    useradd -M -s "$shell_bin" -e "$expiry_date" "$username" >/dev/null 2>&1 || {
        # Fallback sin -e si la flag no es soportada
        useradd -M -s "$shell_bin" "$username" >/dev/null 2>&1 || {
            tc_msg_err "Error al crear el usuario en el sistema."
            tc_pause
            return 1
        }
        chage -E "$expiry_date" "$username" >/dev/null 2>&1 || true
    }

    echo "${username}:${password}" | chpasswd >/dev/null 2>&1

    # 6. Guardar en Base de Datos y archivo de contraseñas
    echo "$password" > "${TC_PASS_DIR}/${username}"
    chmod 600 "${TC_PASS_DIR}/${username}"

    # Eliminar entrada previa si existía y agregar nueva
    sed -i "/^[[:space:]]*${username}[[:space:]]*|/d" "$TC_USERS_DB" 2>/dev/null || true
    echo "${username} | ${password} | ${expiry_date} | ${limit}" >> "$TC_USERS_DB"

    # 7. Sincronizar Hysteria si está presente
    if [[ -x "/etc/tunnelcore/protocols/hysteria.sh" ]]; then
        /etc/tunnelcore/protocols/hysteria.sh --sync >/dev/null 2>&1 || true
    fi

    # 8. Mostrar Ficha de Acceso
    local vps_ip
    vps_ip="$(tc_public_ip)"

    tc_clear
    tc_title "USUARIO CREADO CON ÉXITO"
    printf '%b%-24s%b %b%s%b\n' "$TC_DARK_GREEN" "IP / HOST:" "$TC_NC" "$TC_WHITE" "$vps_ip" "$TC_NC"
    printf '%b%-24s%b %b%s%b\n' "$TC_DARK_GREEN" "USUARIO:" "$TC_NC" "$TC_WHITE" "$username" "$TC_NC"
    printf '%b%-24s%b %b%s%b\n' "$TC_DARK_GREEN" "CONTRASEÑA:" "$TC_NC" "$TC_WHITE" "$password" "$TC_NC"
    printf '%b%-24s%b %b%s (%s días)%b\n' "$TC_DARK_GREEN" "EXPIRA EL:" "$TC_NC" "$TC_WHITE" "$expiry_date" "$days" "$TC_NC"
    printf '%b%-24s%b %b%s%b\n' "$TC_DARK_GREEN" "LÍMITE CONEXIONES:" "$TC_NC" "$TC_WHITE" "$limit" "$TC_NC"
    tc_line
    tc_pause
}

# ── 2. ELIMINAR USUARIO ───────────────────────────────────────
tc_user_remove() {
    tc_users_init
    tc_clear
    tc_title "ELIMINAR USUARIO SSH/VPN"

    if [[ ! -s "$TC_USERS_DB" ]]; then
        tc_msg_warn "No hay usuarios registrados en TunnelCore."
        tc_pause
        return
    fi

    local -a user_list=()
    while IFS='|' read -r u _pass _exp _lim; do
        u="$(echo "$u" | xargs)"
        [[ -n "$u" ]] && user_list+=("$u")
    done < "$TC_USERS_DB"

    if [[ ${#user_list[@]} -eq 0 ]]; then
        tc_msg_warn "No se encontraron usuarios en la lista."
        tc_pause
        return
    fi

    printf '%b%-6s %-20s%b\n' "$TC_WHITE" "NUM" "USUARIO" "$TC_NC"
    tc_line
    for i in "${!user_list[@]}"; do
        tc_opt "$((i + 1))" "${user_list[$i]}"
    done
    tc_line
    tc_opt "0" "CANCELAR"
    tc_line

    local sel
    while true; do
        tc_prompt "Seleccione usuario a eliminar"
        read -r sel
        [[ "$sel" == "0" ]] && return
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#user_list[@]} )); then
            break
        fi
        tc_msg_err "Opción no válida."
    done

    local target_user="${user_list[$((sel - 1))]}"

    if tc_confirm "¿Está seguro de eliminar al usuario '$target_user'?"; then
        # Matar procesos del usuario
        pkill -u "$target_user" >/dev/null 2>&1 || true
        # Eliminar usuario del sistema
        userdel -f "$target_user" >/dev/null 2>&1 || true
        # Eliminar de la base de datos
        sed -i "/^[[:space:]]*${target_user}[[:space:]]*|/d" "$TC_USERS_DB" 2>/dev/null || true
        rm -f "${TC_PASS_DIR}/${target_user}" 2>/dev/null || true

        # Sincronizar Hysteria si aplica
        if [[ -x "/etc/tunnelcore/protocols/hysteria.sh" ]]; then
            /etc/tunnelcore/protocols/hysteria.sh --sync >/dev/null 2>&1 || true
        fi

        tc_msg_ok "Usuario '$target_user' eliminado correctamente."
    else
        tc_msg_warn "Operación cancelada."
    fi
    tc_pause
}

# ── 3. RENOVAR / CAMBIAR FECHA ────────────────────────────────
tc_user_renew() {
    tc_users_init
    tc_clear
    tc_title "RENOVAR / CAMBIAR EXPIRACIÓN"

    if [[ ! -s "$TC_USERS_DB" ]]; then
        tc_msg_warn "No hay usuarios registrados."
        tc_pause
        return
    fi

    printf '%bNombre del usuario a renovar:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r username
    username="$(echo "$username" | tr -d ' ')"

    if ! tc_user_exists "$username"; then
        tc_msg_err "El usuario '$username' no existe."
        tc_pause
        return
    fi

    local days
    while true; do
        printf '%bCantidad de días a añadir [1-365]:%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r days
        if [[ ! "$days" =~ ^[0-9]+$ ]] || (( days < 1 || days > 365 )); then
            tc_msg_err "Ingrese un número válido de días."
            continue
        fi
        break
    done

    local new_expiry
    new_expiry="$(date '+%Y-%m-%d' -d "+${days} days" 2>/dev/null || date -v "+${days}d" '+%Y-%m-%d')"

    chage -E "$new_expiry" "$username" >/dev/null 2>&1 || usermod -e "$new_expiry" "$username" >/dev/null 2>&1 || true

    # Actualizar DB
    local cur_pass cur_lim
    cur_pass="$(awk -F'|' -v u="$username" '$1 ~ u {gsub(/ /,"",$2); print $2}' "$TC_USERS_DB" | head -1)"
    cur_lim="$(awk -F'|' -v u="$username" '$1 ~ u {gsub(/ /,"",$4); print $4}' "$TC_USERS_DB" | head -1)"
    [[ -z "$cur_lim" ]] && cur_lim="1"

    sed -i "/^[[:space:]]*${username}[[:space:]]*|/d" "$TC_USERS_DB" 2>/dev/null || true
    echo "${username} | ${cur_pass} | ${new_expiry} | ${cur_lim}" >> "$TC_USERS_DB"

    tc_msg_ok "Usuario '$username' renovado hasta: $new_expiry ($days días adicionales)."
    tc_pause
}

# ── 4. CAMBIAR CONTRASEÑA ─────────────────────────────────────
tc_user_change_pass() {
    tc_users_init
    tc_clear
    tc_title "CAMBIAR CONTRASEÑA"

    printf '%bNombre del usuario:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r username
    username="$(echo "$username" | tr -d ' ')"

    if ! tc_user_exists "$username"; then
        tc_msg_err "El usuario '$username' no existe."
        tc_pause
        return
    fi

    printf '%bNueva contraseña:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r new_pass
    [[ -z "$new_pass" ]] && {
        tc_msg_err "La contraseña no puede estar vacía."
        tc_pause
        return
    }

    echo "${username}:${new_pass}" | chpasswd >/dev/null 2>&1
    echo "$new_pass" > "${TC_PASS_DIR}/${username}"

    # Actualizar DB
    local cur_exp cur_lim
    cur_exp="$(awk -F'|' -v u="$username" '$1 ~ u {gsub(/ /,"",$3); print $3}' "$TC_USERS_DB" | head -1)"
    cur_lim="$(awk -F'|' -v u="$username" '$1 ~ u {gsub(/ /,"",$4); print $4}' "$TC_USERS_DB" | head -1)"
    [[ -z "$cur_lim" ]] && cur_lim="1"

    sed -i "/^[[:space:]]*${username}[[:space:]]*|/d" "$TC_USERS_DB" 2>/dev/null || true
    echo "${username} | ${new_pass} | ${cur_exp} | ${cur_lim}" >> "$TC_USERS_DB"

    # Sincronizar Hysteria si aplica
    if [[ -x "/etc/tunnelcore/protocols/hysteria.sh" ]]; then
        /etc/tunnelcore/protocols/hysteria.sh --sync >/dev/null 2>&1 || true
    fi

    tc_msg_ok "Contraseña de '$username' actualizada con éxito."
    tc_pause
}

# ── 5. CAMBIAR LÍMITE DE CONEXIONES ───────────────────────────
tc_user_change_limit() {
    tc_users_init
    tc_clear
    tc_title "CAMBIAR LÍMITE DE CONEXIONES"

    printf '%bNombre del usuario:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r username
    username="$(echo "$username" | tr -d ' ')"

    if ! tc_user_exists "$username"; then
        tc_msg_err "El usuario '$username' no existe."
        tc_pause
        return
    fi

    local new_limit
    while true; do
        printf '%bNuevo límite de conexiones [1-999]:%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r new_limit
        if [[ ! "$new_limit" =~ ^[0-9]+$ ]] || (( new_limit < 1 || new_limit > 999 )); then
            tc_msg_err "Ingrese un límite válido (1 a 999)."
            continue
        fi
        break
    done

    # Actualizar DB
    local cur_pass cur_exp
    cur_pass="$(awk -F'|' -v u="$username" '$1 ~ u {gsub(/ /,"",$2); print $2}' "$TC_USERS_DB" | head -1)"
    cur_exp="$(awk -F'|' -v u="$username" '$1 ~ u {gsub(/ /,"",$3); print $3}' "$TC_USERS_DB" | head -1)"

    sed -i "/^[[:space:]]*${username}[[:space:]]*|/d" "$TC_USERS_DB" 2>/dev/null || true
    echo "${username} | ${cur_pass} | ${cur_exp} | ${new_limit}" >> "$TC_USERS_DB"

    tc_msg_ok "Límite de conexiones para '$username' actualizado a: $new_limit"
    tc_pause
}

# ── 6. LISTAR USUARIOS ────────────────────────────────────────
tc_user_list() {
    tc_users_init
    tc_clear
    tc_title "USUARIOS REGISTRADOS"

    if [[ ! -s "$TC_USERS_DB" ]]; then
        tc_msg_warn "No hay usuarios registrados."
        tc_pause
        return
    fi

    printf '%b%-16s %-12s %-12s %-8s %s%b\n' "$TC_WHITE" "USUARIO" "CONEXIONES" "EXPIRA" "DIAS" "LIMITE" "$TC_NC"
    tc_line

    local today_sec
    today_sec="$(date +%s)"

    while IFS='|' read -r user pass expiry limit; do
        user="$(echo "$user" | xargs)"
        pass="$(echo "$pass" | xargs)"
        expiry="$(echo "$expiry" | xargs)"
        limit="$(echo "$limit" | xargs)"
        [[ -z "$user" ]] && continue

        local act_conns exp_disp days_disp
        act_conns="$(tc_user_active_conns "$user")"

        if [[ -n "$expiry" ]]; then
            local exp_sec
            exp_sec="$(date +%s --date="$expiry" 2>/dev/null || echo "0")"
            if (( exp_sec > 0 )); then
                if (( today_sec > exp_sec )); then
                    days_disp="${TC_RED}EXP${TC_NC}"
                    exp_disp="${TC_RED}${expiry}${TC_NC}"
                else
                    local diff_days=$(( (exp_sec - today_sec) / 86400 ))
                    days_disp="${TC_GREEN}${diff_days}d${TC_NC}"
                    exp_disp="${TC_WHITE}${expiry}${TC_NC}"
                fi
            else
                days_disp="${TC_YELLOW}S/R${TC_NC}"
                exp_disp="${TC_WHITE}${expiry}${TC_NC}"
            fi
        else
            days_disp="${TC_YELLOW}S/R${TC_NC}"
            exp_disp="N/A"
        fi

        printf '%b%-16s%b %b%-12s%b %-12b %-8b %b%s%b\n' \
            "$TC_CYAN" "$user" "$TC_NC" \
            "$TC_PALE_GOLD" "${act_conns}/${limit}" "$TC_NC" \
            "$exp_disp" \
            "$days_disp" \
            "$TC_WHITE" "$limit" "$TC_NC"
    done < "$TC_USERS_DB"

    tc_line
    tc_pause
}

# ── 7. LIMPIAR USUARIOS EXPIRADOS ─────────────────────────────
tc_user_cleanup_expired() {
    tc_users_init
    tc_clear
    tc_title "LIMPIAR USUARIOS EXPIRADOS"

    if [[ ! -s "$TC_USERS_DB" ]]; then
        tc_msg_warn "No hay usuarios registrados."
        tc_pause
        return
    fi

    local today_sec count_del=0
    today_sec="$(date +%s)"
    local -a expired_list=()

    while IFS='|' read -r user _pass expiry _lim; do
        user="$(echo "$user" | xargs)"
        expiry="$(echo "$expiry" | xargs)"
        [[ -z "$user" || -z "$expiry" ]] && continue
        local exp_sec
        exp_sec="$(date +%s --date="$expiry" 2>/dev/null || echo "0")"
        if (( exp_sec > 0 && today_sec > exp_sec )); then
            expired_list+=("$user")
        fi
    done < "$TC_USERS_DB"

    if [[ ${#expired_list[@]} -eq 0 ]]; then
        tc_msg_ok "No se encontraron usuarios expirados."
        tc_pause
        return
    fi

    echo -e "${TC_YELLOW}Usuarios expirados encontrados (${#expired_list[@]}):${TC_NC}"
    for u in "${expired_list[@]}"; do
        printf '  • %b%s%b\n' "$TC_RED" "$u" "$TC_NC"
    done
    tc_line

    if tc_confirm "¿Desea eliminar todos los usuarios expirados de la lista?"; then
        for u in "${expired_list[@]}"; do
            pkill -u "$u" >/dev/null 2>&1 || true
            userdel -f "$u" >/dev/null 2>&1 || true
            sed -i "/^[[:space:]]*${u}[[:space:]]*|/d" "$TC_USERS_DB" 2>/dev/null || true
            rm -f "${TC_PASS_DIR}/${u}" 2>/dev/null || true
            (( count_del++ ))
        done

        if [[ -x "/etc/tunnelcore/protocols/hysteria.sh" ]]; then
            /etc/tunnelcore/protocols/hysteria.sh --sync >/dev/null 2>&1 || true
        fi

        tc_msg_ok "Se eliminaron $count_del usuarios expirados con éxito."
    else
        tc_msg_warn "Operación cancelada."
    fi
    tc_pause
}

# ── MENÚ DE USUARIOS ──────────────────────────────────────────
tc_users_menu() {
    while true; do
        tc_clear
        tc_title "ADMINISTRAR USUARIOS"
        tc_opt "1" "CREAR USUARIO"
        tc_opt "2" "ELIMINAR USUARIO"
        tc_opt "3" "RENOVAR / CAMBIAR EXPIRACIÓN"
        tc_opt "4" "CAMBIAR CONTRASEÑA"
        tc_opt "5" "CAMBIAR LÍMITE DE CONEXIONES"
        tc_opt "6" "LISTAR USUARIOS"
        tc_opt "7" "LIMPIAR USUARIOS EXPIRADOS"
        tc_line
        tc_opt "0" "VOLVER AL MENÚ PRINCIPAL"
        tc_line

        tc_prompt
        read -r u_opt

        case "$u_opt" in
            1|01) tc_user_create ;;
            2|02) tc_user_remove ;;
            3|03) tc_user_renew ;;
            4|04) tc_user_change_pass ;;
            5|05) tc_user_change_limit ;;
            6|06) tc_user_list ;;
            7|07) tc_user_cleanup_expired ;;
            0|00) break ;;
            *)
                tc_msg_err "Opción no válida."
                sleep 1
                ;;
        esac
    done
}

