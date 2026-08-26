#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/users.sh
#  Gestión Avanzada de Usuarios SSH / Dropbear / VPN (1:1 NoxuraSSH)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════

TC_USERS_DIR="/etc/tunnelcore"
TC_USERS_DB="${TC_USERS_DIR}/users.db"
TC_PASS_DIR="${TC_USERS_DIR}/passwords"
TC_TEST_DIR="/etc/tunnelcore/usertest"

tc_users_init() {
    mkdir -p "$TC_USERS_DIR" "$TC_PASS_DIR" "$TC_TEST_DIR" /etc/SSHPlus/senha /etc/SSHPlus/userteste
    chmod 700 "$TC_PASS_DIR"
    [[ -f "$TC_USERS_DB" ]] || touch "$TC_USERS_DB"
    chmod 600 "$TC_USERS_DB"
    [[ -f /root/usuarios.db ]] || touch /root/usuarios.db

    # Registrar shells en /etc/shells para Dropbear y PAM
    grep -qxF "/bin/false" /etc/shells 2>/dev/null || echo "/bin/false" >> /etc/shells
    grep -qxF "/usr/sbin/nologin" /etc/shells 2>/dev/null || echo "/usr/sbin/nologin" >> /etc/shells

    # Instalar comando 'at' si no está presente para los usuarios temporales
    if ! command -v at >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y at >/dev/null 2>&1 || true
        systemctl enable --now atd >/dev/null 2>&1 || true
    fi
}

tc_valid_username() {
    local u="$1"
    [[ "$u" =~ ^[a-zA-Z0-9_-]{2,20}$ ]]
}

tc_user_exists() {
    local u="$1"
    id "$u" >/dev/null 2>&1 || grep -qE "^[[:space:]]*${u}[[:space:]]*\|" "$TC_USERS_DB" 2>/dev/null || grep -qw "$u" /root/usuarios.db 2>/dev/null
}

tc_get_user_password() {
    local u="$1"
    if [[ -f "${TC_PASS_DIR}/${u}" ]]; then
        cat "${TC_PASS_DIR}/${u}"
    elif [[ -f "/etc/SSHPlus/senha/${u}" ]]; then
        cat "/etc/SSHPlus/senha/${u}"
    else
        echo "—"
    fi
}

tc_get_user_limit() {
    local u="$1"
    local lim
    lim="$(grep -E "^[[:space:]]*${u}[[:space:]]*\|" "$TC_USERS_DB" 2>/dev/null | cut -d'|' -f3 | tr -d ' ')"
    [[ -z "$lim" ]] && lim="$(grep -w "^$u" /root/usuarios.db 2>/dev/null | awk '{print $2}')"
    [[ -z "$lim" || ! "$lim" =~ ^[0-9]+$ ]] && lim=1
    echo "$lim"
}

tc_user_active_conns() {
    local u="$1"
    local sqd=0 ovp=0 drp=0
    sqd="$(ps -u "$u" 2>/dev/null | grep 'sshd' | wc -l)"
    [[ ! "$sqd" =~ ^[0-9]+$ ]] && sqd=0

    if [[ -e /etc/openvpn/openvpn-status.log ]]; then
        ovp="$(grep -E ,"$u", /etc/openvpn/openvpn-status.log 2>/dev/null | wc -l)"
    fi
    [[ ! "$ovp" =~ ^[0-9]+$ ]] && ovp=0

    drp="$(ps aux 2>/dev/null | grep dropbear | grep -w "$u" | grep -v grep | wc -l)"
    [[ ! "$drp" =~ ^[0-9]+$ ]] && drp=0

    echo "$((sqd + ovp + drp))"
}

tc_get_user_exp_days() {
    local user="$1" raw exp today days db_exp now left mins
    db_exp="$(grep -E "^[[:space:]]*${user}[[:space:]]*\|" "$TC_USERS_DB" 2>/dev/null | tail -1 | cut -d'|' -f2 | tr -d ' ')"
    if [[ "$db_exp" =~ ^test:([0-9]+):([0-9]+)$ ]]; then
        now="$(date +%s)"
        exp="${BASH_REMATCH[1]}"
        if (( now >= exp )); then
            echo "Vencido"
        else
            left=$((exp - now))
            mins=$(( (left + 59) / 60 ))
            echo "${mins} Minutos"
        fi
        return
    fi
    raw="$(chage -l "$user" 2>/dev/null | awk -F: '/Account expires|La cuenta caduca|Cuenta expira|conta expira/ {gsub(/^ +/,"",$2); print $2; exit}')"
    [[ -z "$raw" ]] && raw="$(chage -l "$user" 2>/dev/null | grep -iE 'expires|caduca|expira' | head -1 | awk -F: '{gsub(/^ +/,"",$2); print $2}')"
    if [[ -z "$raw" || "$raw" =~ ^(never|nunca)$ ]]; then
        echo "Nunca"
        return
    fi
    exp="$(date -d "$raw" +%s 2>/dev/null)"
    today="$(date -d today +%s 2>/dev/null)"
    if [[ -z "$exp" || -z "$today" ]]; then
        echo "S/R"
    elif [[ "$today" -ge "$exp" ]]; then
        echo "Vencido"
    else
        days=$(( (exp - today) / 86400 ))
        echo "$days días"
    fi
}

tc_sync_user_databases() {
    local u="$1" p="$2" l="$3" exp="$4"
    mkdir -p "$TC_USERS_DIR" "$TC_PASS_DIR" /etc/SSHPlus/senha
    echo "$p" > "${TC_PASS_DIR}/${u}"
    echo "$p" > "/etc/SSHPlus/senha/${u}"
    chmod 600 "${TC_PASS_DIR}/${u}" "/etc/SSHPlus/senha/${u}" 2>/dev/null || true

    sed -i "/^[[:space:]]*${u}[[:space:]]*|/d" "$TC_USERS_DB" 2>/dev/null || true
    echo "${u} | ${exp} | ${l} | $(date +%Y-%m-%d)" >> "$TC_USERS_DB"

    sed -i "/^${u}[[:space:]]/d" /root/usuarios.db 2>/dev/null || true
    echo "${u} ${l}" >> /root/usuarios.db

    if [[ -x "/etc/tunnelcore/protocols/hysteria.sh" ]]; then
        /etc/tunnelcore/protocols/hysteria.sh --sync >/dev/null 2>&1 || true
    fi
}

# ── 1. CREAR USUARIO ──────────────────────────────────────────
tc_user_create() {
    tc_users_init
    tc_clear
    tc_title "CREAR NUEVO USUARIO SSH/VPN"

    local username password days limit expiry_date

    while true; do
        printf '%bNombre de usuario (2-20 carácteres):%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r username
        username="$(echo "$username" | tr -d ' ')"
        if [[ -z "$username" ]]; then
            tc_msg_err "El nombre de usuario no puede estar vacío."
            continue
        elif ! tc_valid_username "$username"; then
            tc_msg_err "Solo se permiten letras, números, guiones (-) y (_)."
            continue
        elif tc_user_exists "$username"; then
            tc_msg_err "El usuario '$username' ya existe en el sistema."
            continue
        fi
        break
    done

    while true; do
        printf '%bContraseña (Enter para generar aleatoria):%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r password
        if [[ -z "$password" ]]; then
            password="$(tc_rand_string 8)"
            printf '%bContraseña generada:%b %b%s%b\n' "$TC_YELLOW" "$TC_NC" "$TC_GREEN" "$password" "$TC_NC"
        fi
        break
    done

    while true; do
        printf '%bDuración en días [1-365] (Enter = 30):%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r days
        [[ -z "$days" ]] && days="30"
        if [[ ! "$days" =~ ^[0-9]+$ ]] || (( days < 1 || days > 365 )); then
            tc_msg_err "Ingrese un número válido de días (1 a 365)."
            continue
        fi
        break
    done

    expiry_date="$(date '+%Y-%m-%d' -d "+${days} days" 2>/dev/null || date -v "+${days}d" '+%Y-%m-%d')"

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

    useradd -M -s /bin/false "$username" 2>/dev/null || {
        tc_msg_err "Error al crear el usuario en el sistema."
        tc_pause
        return 1
    }
    (echo "$password"; echo "$password") | passwd "$username" >/dev/null 2>&1
    chage -E "$expiry_date" "$username" 2>/dev/null || true

    tc_sync_user_databases "$username" "$password" "$limit" "$expiry_date"

    local server_ip
    server_ip="$(tc_public_ip)"

    tc_clear
    tc_title "DATOS DE ACCESO"
    printf '%bIP DEL SERVIDOR      :%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$server_ip" "$TC_NC"
    printf '%bUSUARIO              :%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$username" "$TC_NC"
    printf '%bCONTRASEÑA           :%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_YELLOW" "$password" "$TC_NC"
    printf '%bFECHA DE EXPIRACIÓN  :%b %b%s (%s días)%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$expiry_date" "$days" "$TC_NC"
    printf '%bLÍMITE DE CONEXIONES :%b %b%s dispositivo(s)%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_CYAN" "$limit" "$TC_NC"
    tc_line
    tc_pause
}

# ── 2. CREAR PRUEBA (TEST TEMPORAL) ───────────────────────────
tc_user_create_test() {
    tc_users_init
    tc_clear
    tc_title "CREAR USUARIO DE PRUEBA"

    local nome pass limit u_temp
    printf '%bNombre de usuario [Enter = generar automático]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r nome
    [[ -z "$nome" ]] && nome="test$(tc_rand_string 4)"

    if tc_user_exists "$nome"; then
        tc_msg_err "El usuario '$nome' ya existe."
        tc_pause
        return
    fi

    printf '%bContraseña [Enter = generar aleatoria]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r pass
    [[ -z "$pass" ]] && pass="$(tc_rand_string 6)"

    printf '%bLímite de conexiones [Enter = 1]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r limit
    [[ -z "$limit" ]] && limit="1"

    printf '%bDuración de la prueba en Minutos [Enter = 60 min]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r u_temp
    [[ -z "$u_temp" ]] && u_temp="60"
    if ! [[ "$u_temp" =~ ^[0-9]+$ ]] || (( u_temp < 1 )); then
        u_temp="60"
    fi

    useradd -M -s /bin/false "$nome" 2>/dev/null || {
        tc_msg_err "Error al crear usuario de prueba."
        tc_pause
        return
    }
    (echo "$pass"; echo "$pass") | passwd "$nome" >/dev/null 2>&1

    local exp_date exp_ts
    exp_ts="$(date -d "+${u_temp} minutes" +%s 2>/dev/null || echo $(( $(date +%s) + (u_temp * 60) )))"
    exp_date="test:${exp_ts}:${u_temp}"
    tc_sync_user_databases "$nome" "$pass" "$limit" "$exp_date"

    # Script de autodestrucción
    local script_file="/etc/tunnelcore/usertest/${nome}.sh"
    cat > "$script_file" <<EOF
#!/bin/bash
pkill -f "$nome" 2>/dev/null
userdel -f "$nome" 2>/dev/null
sed -i "/^[[:space:]]*${nome}[[:space:]]*|/d" /etc/tunnelcore/users.db 2>/dev/null
sed -i "/^${nome}[[:space:]]/d" /root/usuarios.db 2>/dev/null
rm -f "/etc/tunnelcore/passwords/$nome" "/etc/SSHPlus/senha/$nome" "$script_file" "/etc/SSHPlus/userteste/$nome.sh" 2>/dev/null
exit 0
EOF
    chmod +x "$script_file"
    cp -f "$script_file" "/etc/SSHPlus/userteste/${nome}.sh" 2>/dev/null || true

    if command -v at >/dev/null 2>&1; then
        at -f "$script_file" now + "$u_temp" min >/dev/null 2>&1 || true
    else
        ( sleep $(( u_temp * 60 )) && bash "$script_file" ) >/dev/null 2>&1 &
    fi

    local server_ip
    server_ip="$(tc_public_ip)"

    tc_clear
    tc_title "USUARIO DE PRUEBA CREADO"
    printf '%bIP DEL SERVIDOR      :%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$server_ip" "$TC_NC"
    printf '%bUSUARIO TEMPORAL     :%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$nome" "$TC_NC"
    printf '%bCONTRASEÑA           :%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_YELLOW" "$pass" "$TC_NC"
    printf '%bLÍMITE DE DISPOSITIVOS:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_CYAN" "$limit" "$TC_NC"
    printf '%bTIEMPO DE PRUEBA     :%b %b%s minutos%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "$u_temp" "$TC_NC"
    tc_line
    printf '%bTras expirar los %s minutos, la cuenta será desconectada y eliminada automáticamente.%b\n' "$TC_WHITE" "$u_temp" "$TC_NC"
    tc_line
    tc_pause
}

# ── 3. ELIMINAR USUARIO ───────────────────────────────────────
tc_user_remove() {
    tc_clear
    tc_title "ELIMINAR USUARIO SSH/VPN"

    mapfile -t all_users < <(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | sort)
    if [[ ${#all_users[@]} -eq 0 ]]; then
        tc_msg_warn "No hay usuarios SSH en el sistema."
        tc_pause
        return
    fi

    local idx=1
    printf '%b%-4s %-20s %-14s %s%b\n' "$TC_YELLOW" "NUM" "USUARIO" "EXPIRA" "ESTADO" "$TC_NC"
    tc_line

    for u in "${all_users[@]}"; do
        local exp_d
        exp_d="$(tc_get_user_exp_days "$u")"
        local conns
        conns="$(tc_user_active_conns "$u")"
        local st
        if (( conns > 0 )); then
            st="${TC_GREEN}ONLINE ($conns)${TC_NC}"
        else
            st="${TC_WHITE}OFFLINE${TC_NC}"
        fi

        printf '%b[%d]%b > %b%-20s%b %-14s %b\n' \
            "$TC_GREEN" "$idx" "$TC_NC" \
            "$TC_WHITE" "$u" "$TC_NC" \
            "$exp_d" "$st"
        ((idx++))
    done

    tc_line
    tc_opt "0" "$(_t 'cancel')"
    tc_line
    tc_prompt "Seleccione usuario a eliminar (o escriba el nombre)"
    read -r sel

    [[ "$sel" == "0" || -z "$sel" ]] && return

    local target_user=""
    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#all_users[@]} )); then
        target_user="${all_users[$((sel - 1))]}"
    else
        target_user="$(echo "$sel" | tr -d ' ')"
    fi

    if ! id "$target_user" >/dev/null 2>&1; then
        tc_msg_err "Usuario '$target_user' no existe."
        tc_pause
        return
    fi

    if ! tc_confirm "¿Está seguro de eliminar por completo a '$target_user'?"; then
        tc_msg_warn "Operación cancelada."
        tc_pause
        return
    fi

    pkill -u "$target_user" >/dev/null 2>&1 || true
    userdel -f "$target_user" >/dev/null 2>&1 || true
    sed -i "/^[[:space:]]*${target_user}[[:space:]]*|/d" "$TC_USERS_DB" 2>/dev/null || true
    sed -i "/^${target_user}[[:space:]]/d" /root/usuarios.db 2>/dev/null || true
    rm -f "${TC_PASS_DIR}/${target_user}" "/etc/SSHPlus/senha/${target_user}" "/etc/tunnelcore/usertest/${target_user}.sh" 2>/dev/null || true

    if [[ -x "/etc/tunnelcore/protocols/hysteria.sh" ]]; then
        /etc/tunnelcore/protocols/hysteria.sh --sync >/dev/null 2>&1 || true
    fi

    tc_msg_ok "Usuario '$target_user' eliminado con éxito."
    tc_pause
}

# ── 4. MONITOR ONLINE EN TIEMPO REAL ──────────────────────────
tc_user_monitor() {
    tc_clear
    tc_title "MONITOR DE CONEXIONES EN VIVO"

    mapfile -t all_users < <(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | sort)
    if [[ ${#all_users[@]} -eq 0 ]]; then
        tc_msg_warn "No hay usuarios creados en el sistema."
        tc_pause
        return
    fi

    printf '%b%-20s %-15s %-15s %s%b\n' "$TC_CYAN" "USUARIO" "ESTADO" "CONECTADOS" "LÍMITE" "$TC_NC"
    tc_line

    local total_online=0
    for u in "${all_users[@]}"; do
        local conns limit
        conns="$(tc_user_active_conns "$u")"
        limit="$(tc_get_user_limit "$u")"

        if (( conns > 0 )); then
            (( total_online += conns ))
            printf '%b%-20s%b %b%-15s%b %b%-15s%b %s\n' \
                "$TC_WHITE" "$u" "$TC_NC" \
                "$TC_GREEN" "ONLINE" "$TC_NC" \
                "$TC_GREEN" "$conns" "$TC_NC" \
                "$limit"
        else
            printf '%b%-20s%b %b%-15s%b %b%-15s%b %s\n' \
                "$TC_WHITE" "$u" "$TC_NC" \
                "$TC_WHITE" "OFFLINE" "$TC_NC" \
                "$TC_WHITE" "0" "$TC_NC" \
                "$limit"
        fi
    done

    tc_line
    printf '%bTotal de conexiones activas en el servidor:%b %b%s%b\n' "$TC_YELLOW" "$TC_NC" "$TC_GREEN" "$total_online" "$TC_NC"
    tc_line
    tc_pause
}

# ── 5. CAMBIAR FECHA / RENOVAR ────────────────────────────────
tc_user_change_date() {
    tc_clear
    tc_title "CAMBIAR FECHA DE EXPIRACIÓN"

    mapfile -t all_users < <(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | sort)
    if [[ ${#all_users[@]} -eq 0 ]]; then
        tc_msg_warn "No hay usuarios registrados."
        tc_pause
        return
    fi

    local idx=1
    printf '%b%-4s %-22s %-16s%b\n' "$TC_YELLOW" "NUM" "USUARIO" "EXPIRA ACTUAL" "$TC_NC"
    tc_line

    for u in "${all_users[@]}"; do
        local exp_d
        exp_d="$(tc_get_user_exp_days "$u")"
        printf '%b[%d]%b > %b%-22s%b %s\n' \
            "$TC_GREEN" "$idx" "$TC_NC" \
            "$TC_WHITE" "$u" "$TC_NC" \
            "$exp_d"
        ((idx++))
    done

    tc_line
    tc_opt "0" "$(_t 'cancel')"
    tc_line
    tc_prompt "Seleccione usuario"
    read -r sel

    [[ "$sel" == "0" || -z "$sel" ]] && return

    local target_user=""
    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#all_users[@]} )); then
        target_user="${all_users[$((sel - 1))]}"
    else
        target_user="$(echo "$sel" | tr -d ' ')"
    fi

    if ! id "$target_user" >/dev/null 2>&1; then
        tc_msg_err "Usuario inválido."
        tc_pause
        return
    fi

    printf '%bDías adicionales a sumar a partir de hoy [1-365] (o Enter = 30):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r add_days
    [[ -z "$add_days" ]] && add_days="30"
    if ! [[ "$add_days" =~ ^[0-9]+$ ]] || (( add_days < 1 || add_days > 365 )); then
        tc_msg_err "Número de días inválido."
        tc_pause
        return
    fi

    local new_exp
    new_exp="$(date '+%Y-%m-%d' -d "+${add_days} days" 2>/dev/null || date -v "+${add_days}d" '+%Y-%m-%d')"
    chage -E "$new_exp" "$target_user" 2>/dev/null || true

    local cur_pass cur_lim
    cur_pass="$(tc_get_user_password "$target_user")"
    cur_lim="$(tc_get_user_limit "$target_user")"
    tc_sync_user_databases "$target_user" "$cur_pass" "$cur_lim" "$new_exp"

    tc_msg_ok "Fecha de expiración para '$target_user' actualizada a: $new_exp ($add_days días)."
    tc_pause
}

# ── 6. CAMBIAR LÍMITE DE CONEXIONES ───────────────────────────
tc_user_change_limit() {
    tc_clear
    tc_title "CAMBIAR LÍMITE DE CONEXIONES"

    mapfile -t all_users < <(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | sort)
    if [[ ${#all_users[@]} -eq 0 ]]; then
        tc_msg_warn "No hay usuarios registrados."
        tc_pause
        return
    fi

    local idx=1
    printf '%b%-4s %-25s %s%b\n' "$TC_YELLOW" "NUM" "USUARIO" "LÍMITE ACTUAL" "$TC_NC"
    tc_line

    for u in "${all_users[@]}"; do
        local cur_lim
        cur_lim="$(tc_get_user_limit "$u")"
        printf '%b[%d]%b > %b%-25s%b %s\n' \
            "$TC_GREEN" "$idx" "$TC_NC" \
            "$TC_WHITE" "$u" "$TC_NC" \
            "$cur_lim"
        ((idx++))
    done

    tc_line
    tc_opt "0" "$(_t 'cancel')"
    tc_line
    tc_prompt "Seleccione usuario"
    read -r sel

    [[ "$sel" == "0" || -z "$sel" ]] && return

    local target_user=""
    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#all_users[@]} )); then
        target_user="${all_users[$((sel - 1))]}"
    else
        target_user="$(echo "$sel" | tr -d ' ')"
    fi

    if ! id "$target_user" >/dev/null 2>&1; then
        tc_msg_err "Usuario no encontrado."
        tc_pause
        return
    fi

    printf '%bNuevo límite de conexiones simultáneas [1-999]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r new_lim
    if ! [[ "$new_lim" =~ ^[0-9]+$ ]] || (( new_lim < 1 || new_lim > 999 )); then
        tc_msg_err "Límite inválido."
        tc_pause
        return
    fi

    local cur_pass cur_exp
    cur_pass="$(tc_get_user_password "$target_user")"
    cur_exp="$(grep -E "^[[:space:]]*${target_user}[[:space:]]*\|" "$TC_USERS_DB" 2>/dev/null | cut -d'|' -f2 | tr -d ' ')"
    [[ -z "$cur_exp" ]] && cur_exp="$(date '+%Y-%m-%d')"

    tc_sync_user_databases "$target_user" "$cur_pass" "$new_lim" "$cur_exp"

    tc_msg_ok "Límite para '$target_user' actualizado a: $new_lim conexiones."
    tc_pause
}

# ── 7. CAMBIAR CONTRASEÑA ─────────────────────────────────────
tc_user_change_pass() {
    tc_clear
    tc_title "CAMBIAR CONTRASEÑA DE USUARIO"

    mapfile -t all_users < <(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | sort)
    if [[ ${#all_users[@]} -eq 0 ]]; then
        tc_msg_warn "No hay usuarios registrados."
        tc_pause
        return
    fi

    local idx=1
    printf '%b%-4s %-25s %s%b\n' "$TC_YELLOW" "NUM" "USUARIO" "CLAVE ACTUAL" "$TC_NC"
    tc_line

    for u in "${all_users[@]}"; do
        local cur_p
        cur_p="$(tc_get_user_password "$u")"
        printf '%b[%d]%b > %b%-25s%b %s\n' \
            "$TC_GREEN" "$idx" "$TC_NC" \
            "$TC_WHITE" "$u" "$TC_NC" \
            "$cur_p"
        ((idx++))
    done

    tc_line
    tc_opt "0" "$(_t 'cancel')"
    tc_line
    tc_prompt "Seleccione usuario"
    read -r sel

    [[ "$sel" == "0" || -z "$sel" ]] && return

    local target_user=""
    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#all_users[@]} )); then
        target_user="${all_users[$((sel - 1))]}"
    else
        target_user="$(echo "$sel" | tr -d ' ')"
    fi

    if ! id "$target_user" >/dev/null 2>&1; then
        tc_msg_err "Usuario no encontrado."
        tc_pause
        return
    fi

    printf '%bNueva contraseña para %s:%b ' "$TC_DARK_GREEN" "$target_user" "$TC_NC"
    read -r new_pass
    [[ -z "$new_pass" ]] && { tc_msg_err "Contraseña no puede estar vacía."; tc_pause; return; }

    (echo "$new_pass"; echo "$new_pass") | passwd "$target_user" >/dev/null 2>&1

    local cur_lim cur_exp
    cur_lim="$(tc_get_user_limit "$target_user")"
    cur_exp="$(grep -E "^[[:space:]]*${target_user}[[:space:]]*\|" "$TC_USERS_DB" 2>/dev/null | cut -d'|' -f2 | tr -d ' ')"
    [[ -z "$cur_exp" ]] && cur_exp="$(date '+%Y-%m-%d')"

    tc_sync_user_databases "$target_user" "$new_pass" "$cur_lim" "$cur_exp"

    tc_msg_ok "Contraseña de '$target_user' cambiada exitosamente a: $new_pass"
    tc_pause
}

# ── 8. INFORME DETALLADO DE USUARIOS ──────────────────────────
tc_user_info() {
    tc_clear
    tc_title "INFORME GENERAL DE USUARIOS"

    mapfile -t all_users < <(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | sort)
    if [[ ${#all_users[@]} -eq 0 ]]; then
        tc_msg_warn "No hay usuarios registrados en el servidor."
        tc_pause
        return
    fi

    local total_u=${#all_users[@]}
    local total_on=0 total_exp=0

    printf '%b%-16s %-16s %-14s %-10s %s%b\n' "$TC_CYAN" "USUARIO" "CONTRASEÑA" "EXPIRA" "CONEX/LIM" "ESTADO" "$TC_NC"
    tc_line

    for u in "${all_users[@]}"; do
        local p exp_d conns lim st
        p="$(tc_get_user_password "$u")"
        exp_d="$(tc_get_user_exp_days "$u")"
        conns="$(tc_user_active_conns "$u")"
        lim="$(tc_get_user_limit "$u")"

        if [[ "$exp_d" == "Vencido" ]]; then
            (( total_exp++ ))
            st="${TC_RED}VENCIDO${TC_NC}"
        elif (( conns > 0 )); then
            (( total_on += conns ))
            st="${TC_GREEN}ONLINE${TC_NC}"
        else
            st="${TC_WHITE}OFFLINE${TC_NC}"
        fi

        printf '%b%-16s%b %b%-16s%b %-14s %-10s %b\n' \
            "$TC_WHITE" "$u" "$TC_NC" \
            "$TC_PALE_GOLD" "$p" "$TC_NC" \
            "$exp_d" "${conns}/${lim}" "$st"
    done

    tc_line
    printf '%bTotal Usuarios:%b %b%s%b  |  %bConectados:%b %b%s%b  |  %bExpirados:%b %b%s%b\n' \
        "$TC_YELLOW" "$TC_NC" "$TC_WHITE" "$total_u" "$TC_NC" \
        "$TC_YELLOW" "$TC_NC" "$TC_GREEN" "$total_on" "$TC_NC" \
        "$TC_YELLOW" "$TC_NC" "$TC_RED" "$total_exp" "$TC_NC"
    tc_line
    tc_pause
}

# ── 9. ELIMINAR USUARIOS EXPIRADOS ────────────────────────────
tc_user_cleanup_expired() {
    tc_clear
    tc_title "LIMPIAR USUARIOS EXPIRADOS"

    mapfile -t all_users < <(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | sort)
    local expired_list=()

    for u in "${all_users[@]}"; do
        if [[ "$(tc_get_user_exp_days "$u")" == "Vencido" ]]; then
            expired_list+=("$u")
        fi
    done

    if [[ ${#expired_list[@]} -eq 0 ]]; then
        tc_msg_ok "No hay usuarios expirados en el sistema."
        tc_pause
        return
    fi

    printf '%bSe encontraron los siguientes usuarios expirados:%b\n' "$TC_YELLOW" "$TC_NC"
    for exp_u in "${expired_list[@]}"; do
        printf '  %b-%b %b%s%b\n' "$TC_RED" "$TC_NC" "$TC_WHITE" "$exp_u" "$TC_NC"
    done
    tc_line

    if tc_confirm "¿Desea eliminar todos los usuarios expirados de la lista?"; then
        local count_del=0
        for u in "${expired_list[@]}"; do
            pkill -u "$u" >/dev/null 2>&1 || true
            userdel -f "$u" >/dev/null 2>&1 || true
            sed -i "/^[[:space:]]*${u}[[:space:]]*|/d" "$TC_USERS_DB" 2>/dev/null || true
            sed -i "/^${u}[[:space:]]/d" /root/usuarios.db 2>/dev/null || true
            rm -f "${TC_PASS_DIR}/${u}" "/etc/SSHPlus/senha/${u}" "/etc/tunnelcore/usertest/${u}.sh" 2>/dev/null || true
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

# ── MENÚ MAESTRO DE USUARIOS (2 COLUMNAS 1:1 NOXURASSH) ───────
tc_users_menu() {
    while true; do
        tc_clear
        tc_title "ADMINISTRAR USUARIOS"

        printf '  %b[1]%b > %b%-18s%b   %b[6]%b > %b%-18s%b\n' \
            "$TC_GREEN" "$TC_NC" "$TC_WHITE" "CREAR USUARIO" "$TC_NC" \
            "$TC_GREEN" "$TC_NC" "$TC_WHITE" "CAMBIAR LIMITE" "$TC_NC"

        printf '  %b[2]%b > %b%-18s%b   %b[7]%b > %b%-18s%b\n' \
            "$TC_GREEN" "$TC_NC" "$TC_WHITE" "CREAR PRUEBA" "$TC_NC" \
            "$TC_GREEN" "$TC_NC" "$TC_WHITE" "CAMBIAR CLAVE" "$TC_NC"

        printf '  %b[3]%b > %b%-18s%b   %b[8]%b > %b%-18s%b\n' \
            "$TC_GREEN" "$TC_NC" "$TC_WHITE" "ELIMINAR USUARIO" "$TC_NC" \
            "$TC_GREEN" "$TC_NC" "$TC_WHITE" "INFORME DE USUARIOS" "$TC_NC"

        printf '  %b[4]%b > %b%-18s%b   %b[9]%b > %b%-18s%b\n' \
            "$TC_GREEN" "$TC_NC" "$TC_WHITE" "MONITOR ONLINE" "$TC_NC" \
            "$TC_GREEN" "$TC_NC" "$TC_WHITE" "ELIMINAR CADUCADOS" "$TC_NC"

        printf '  %b[5]%b > %b%-18s%b   %b[0]%b > %b%-18s%b\n' \
            "$TC_GREEN" "$TC_NC" "$TC_WHITE" "CAMBIAR FECHA" "$TC_NC" \
            "$TC_GREEN" "$TC_NC" "$TC_WHITE" "VOLVER" "$TC_NC"

        tc_line
        tc_prompt
        read -r u_opt

        case "$u_opt" in
            1|01) tc_user_create ;;
            2|02) tc_user_create_test ;;
            3|03) tc_user_remove ;;
            4|04) tc_user_monitor ;;
            5|05) tc_user_change_date ;;
            6|06) tc_user_change_limit ;;
            7|07) tc_user_change_pass ;;
            8|08) tc_user_info ;;
            9|09) tc_user_cleanup_expired ;;
            0|00) break ;;
            *)
                tc_msg_err "Opción no válida."
                sleep 1
                ;;
        esac
    done
}
