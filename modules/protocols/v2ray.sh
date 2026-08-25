#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/protocols/v2ray.sh
#  Gestor de V2Ray / Xray Oficial (Multi-V2Ray / Rufus)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

TC_V2_REG="/etc/tunnelcore/v2ray_users.db"
TC_V2_DOMAIN_FILE="/etc/tunnelcore/v2ray_domain"

tc_v2_config_file() {
    local cfg
    for cfg in /etc/v2ray/config.json /usr/local/etc/v2ray/config.json /etc/tunnelcore/v2ray/config.json /usr/local/etc/xray/config.json /etc/xray/config.json; do
        [[ -f "$cfg" ]] && echo "$cfg" && return 0
    done
    return 1
}

tc_v2_is_installed() {
    command -v v2ray >/dev/null 2>&1 || [[ -n "$(tc_v2_config_file)" ]] || command -v xray >/dev/null 2>&1
}

tc_v2_is_running() {
    systemctl is-active --quiet v2ray 2>/dev/null || systemctl is-active --quiet xray 2>/dev/null || pgrep -x v2ray >/dev/null 2>&1 || pgrep -x xray >/dev/null 2>&1
}

tc_v2_status_mark() {
    if tc_v2_is_running; then
        printf '%b[ON]%b' "$TC_GREEN" "$TC_NC"
    elif tc_v2_is_installed; then
        printf '%b[OFF]%b' "$TC_RED" "$TC_NC"
    else
        printf '%b[NO INSTALADO]%b' "$TC_YELLOW" "$TC_NC"
    fi
}

tc_v2_restart() {
    if systemctl is-active v2ray >/dev/null 2>&1 || systemctl list-unit-files v2ray.service >/dev/null 2>&1; then
        systemctl restart v2ray >/dev/null 2>&1 || true
    fi
    if systemctl is-active xray >/dev/null 2>&1 || systemctl list-unit-files xray.service >/dev/null 2>&1; then
        systemctl restart xray >/dev/null 2>&1 || true
    fi
    if command -v v2ray >/dev/null 2>&1; then
        v2ray restart >/dev/null 2>&1 || true
    fi
}

# ── Instalador Oficial Multi-V2Ray (Rufus) ────────────────────
tc_v2_install_official() {
    tc_clear
    tc_title "INSTALAR V2RAY (OFICIAL RUFUS / MULTI-V2RAY)"

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y curl wget unzip ca-certificates jq uuid-runtime >/dev/null 2>&1 || true
    fi

    tc_msg_ok "Descargando e iniciando instalador Multi-V2Ray..."
    
    # Ejecutar instalador oficial
    if ! bash <(curl -sL https://multi.netlify.app/v2ray.sh) -k 2>/dev/null; then
        bash <(curl -sL https://raw.githubusercontent.com/Jrohy/multi-v2ray/master/v2ray.sh) || true
    fi

    mkdir -p /etc/tunnelcore
    touch "$TC_V2_REG"

    local cfg
    cfg="$(tc_v2_config_file)"
    if [[ -n "$cfg" ]]; then
        mkdir -p /etc/v2ray
        ln -sf "$cfg" /etc/v2ray/config.json 2>/dev/null || cp -f "$cfg" /etc/v2ray/config.json 2>/dev/null || true
    fi

    tc_msg_ok "¡Instalación de V2Ray completada!"
    tc_pause
}

# ── Desinstalación Profunda Total de V2Ray / Xray ─────────────
tc_v2_uninstall_all() {
    tc_clear
    tc_title "DESINSTALAR V2RAY / XRAY"

    if ! tc_confirm "¿Está seguro de desinstalar y limpiar por completo V2Ray y Xray?"; then
        return
    fi

    tc_msg_ok "Deteniendo y eliminando servicios..."
    systemctl stop v2ray >/dev/null 2>&1 || true
    systemctl stop xray >/dev/null 2>&1 || true
    systemctl disable v2ray >/dev/null 2>&1 || true
    systemctl disable xray >/dev/null 2>&1 || true

    if command -v v2ray >/dev/null 2>&1; then
        v2ray uninstall >/dev/null 2>&1 || true
    fi

    pkill -9 -x v2ray >/dev/null 2>&1 || true
    pkill -9 -x xray >/dev/null 2>&1 || true

    rm -f /etc/systemd/system/xray.service /etc/systemd/system/v2ray.service /lib/systemd/system/v2ray.service /lib/systemd/system/xray.service /etc/systemd/system/multi-v2ray.service
    systemctl daemon-reload >/dev/null 2>&1 || true

    rm -f /usr/local/bin/xray /usr/local/bin/v2ray /usr/bin/v2ray /usr/bin/xray /bin/v2ray /bin/xray
    rm -rf /etc/v2ray /usr/local/etc/v2ray /etc/xray /usr/local/etc/xray /etc/tunnelcore/v2ray /etc/tunnelcore/v2ray_users.db /etc/tunnelcore/v2ray_domain /etc/tunnelcore/v2ray.env /var/log/v2ray /var/log/xray /root/.v2ray /root/.xray

    tc_msg_ok "¡V2Ray / Xray ha sido desinstalado por completo!"
    tc_pause
}

# ── Agregar Usuario V2Ray (VMess / VLESS con CDN y TLS) ───────
tc_v2_add_user() {
    local cfg
    cfg="$(tc_v2_config_file)"
    if [[ -z "$cfg" ]]; then
        tc_msg_warn "V2Ray no está instalado. Instálelo primero."
        tc_pause
        return
    fi

    tc_clear
    tc_title "AGREGAR USUARIO V2RAY"

    local nick
    while true; do
        printf '%bNombre / Alias del usuario:%b ' "$TC_DARK_GREEN" "$TC_NC"
        read -r nick
        nick="$(echo "$nick" | tr -d ' ')"
        [[ -z "$nick" ]] && { tc_msg_err "El nombre no puede estar vacío."; continue; }
        if grep -qE "\|\s*${nick}\s*\|" "$TC_V2_REG" 2>/dev/null; then
            tc_msg_err "Ya existe un usuario con ese nombre."
            continue
        fi
        break
    done

    # Protocolo
    printf '\n%bSeleccione Protocolo:%b\n' "$TC_WHITE" "$TC_NC"
    tc_opt "1" "VMess (Compatible con todas las aplicaciones)"
    tc_opt "2" "VLESS (Ligero y de alta velocidad)"
    tc_prompt "Opción [1-2]"
    local proto_opt proto_tag="vmess" proto_name="VMess"
    read -r proto_opt
    case "$proto_opt" in
        2) proto_tag="vless"; proto_name="VLESS" ;;
        *) proto_tag="vmess"; proto_name="VMess" ;;
    esac

    # Puerto del servidor
    mapfile -t v2_ports < <(jq -r '.inbounds[]? | select((.settings.clients? | type) == "array") | .port' "$cfg" 2>/dev/null | sed '/^$/d' | sort -n | uniq)
    local selected_port="80"
    if [[ "${#v2_ports[@]}" -gt 0 ]]; then
        selected_port="${v2_ports[0]}"
    fi

    # UUID
    local uuid
    printf '\n%bUUID personalizado (Enter para generar aleatorio):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r uuid
    [[ -z "$uuid" ]] && uuid="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || tc_gen_uuid)"

    # Modo TLS / CDN
    local tls_mode="none" ext_port="$selected_port" add_host sni_host="" host_header=""
    local cur_domain="$(cat "$TC_V2_DOMAIN_FILE" 2>/dev/null || echo "")"
    local vps_ip="$(tc_public_ip)"

    printf '\n%bModo de Conexión / Seguridad:%b\n' "$TC_WHITE" "$TC_NC"
    tc_opt "1" "DIRECTO A IP (Sin TLS / HTTP WS - Puerto $selected_port)"
    tc_opt "2" "CLOUDFLARE CDN / DOMINIO (Con TLS 443 + SNI Bug Host)"
    tc_prompt "Opción [1-2]"
    local conn_opt
    read -r conn_opt

    if [[ "$conn_opt" == "2" ]]; then
        tls_mode="tls"
        ext_port="443"
        if [[ -n "$cur_domain" ]]; then
            printf '\n%bDominio CDN (Enter para usar %s):%b ' "$TC_DARK_GREEN" "$cur_domain" "$TC_NC"
            read -r input_domain
            [[ -n "$input_domain" ]] && add_host="$input_domain" || add_host="$cur_domain"
        else
            while true; do
                printf '\n%bDominio CDN (ej: midominio.com):%b ' "$TC_DARK_GREEN" "$TC_NC"
                read -r add_host
                [[ -n "$add_host" ]] && break
                tc_msg_err "Debe ingresar un dominio."
            done
            echo "$add_host" > "$TC_V2_DOMAIN_FILE"
        fi

        printf '%bSNI / Bug Host (ej: bug.operadora.com) [Enter para usar %s]:%b ' "$TC_DARK_GREEN" "$add_host" "$TC_NC"
        read -r input_sni
        if [[ -n "$input_sni" ]]; then
            sni_host="$input_sni"
            host_header="$input_sni"
        else
            sni_host="$add_host"
            host_header="$add_host"
        fi
    else
        tls_mode="none"
        ext_port="$selected_port"
        add_host="$vps_ip"
    fi

    # Duración en días
    printf '\n%bDuración del usuario en días [1-365] (Enter = 30):%b ' "$TC_DARK_GREEN" "$TC_NC"
    local days
    read -r days
    [[ -z "$days" ]] && days="30"
    local expiry_date="$(date '+%Y-%m-%d' -d "+${days} days" 2>/dev/null || echo "2030-01-01")"

    # Insertar en config.json
    local tmp="${cfg}.tmp"
    jq --arg uuid "$uuid" --arg proto "$proto_tag" '
      .inbounds |= map(
        if ((.settings.clients? | type) == "array") then
          if (.settings.clients | any(.id == $uuid)) then
            .
          else
            .settings.clients += [(
              if ($proto == "vless" or .protocol == "vless") then
                {"id": $uuid, "level": 0}
              else
                {"id": $uuid, "alterId": 0}
              end
            )]
          end
        else
          .
        end
      )
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"

    mkdir -p /etc/tunnelcore
    echo "${uuid} | ${nick} | ${expiry_date} | ${proto_tag}" >> "$TC_V2_REG"
    tc_v2_restart

    # Obtener Path
    local path_ws="$(jq -r '.inbounds[0].streamSettings.wsSettings.path // .inbounds[0].streamSettings.xhttpSettings.path // "/v2ray"' "$cfg" 2>/dev/null)"
    [[ -z "$path_ws" || "$path_ws" == "null" ]] && path_ws="/v2ray"

    # Generar URI
    local uri=""
    if [[ "$proto_tag" == "vmess" ]]; then
        local vmess_json
        vmess_json=$(cat <<EOF
{"v":"2","ps":"${nick}","add":"${add_host}","port":"${ext_port}","id":"${uuid}","aid":"0","scy":"auto","net":"ws","type":"none","host":"${host_header}","path":"${path_ws}","tls":"${tls_mode}","sni":"${sni_host}","alpn":"","fp":""}
EOF
)
        local b64="$(printf '%s' "$vmess_json" | base64 | tr -d '\n\r ')"
        uri="vmess://${b64}"
    else
        local enc_path="$(printf '%s' "$path_ws" | sed 's/\//%2F/g')"
        if [[ "$tls_mode" == "tls" ]]; then
            uri="vless://${uuid}@${add_host}:${ext_port}?type=ws&security=tls&sni=${sni_host}&host=${host_header}&path=${enc_path}#${nick}"
        else
            uri="vless://${uuid}@${add_host}:${ext_port}?type=ws&security=none&path=${enc_path}#${nick}"
        fi
    fi

    tc_clear
    tc_title "USUARIO V2RAY CREADO CON ÉXITO"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "USUARIO:" "$TC_NC" "$TC_WHITE" "$nick" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "PROTOCOLO:" "$TC_NC" "$TC_WHITE" "$proto_name" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "UUID / ID:" "$TC_NC" "$TC_WHITE" "$uuid" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "SERVIDOR (ADD):" "$TC_NC" "$TC_WHITE" "$add_host" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "PUERTO:" "$TC_NC" "$TC_WHITE" "$ext_port" "$TC_NC"
    [[ "$tls_mode" == "tls" ]] && printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "SNI / BUG HOST:" "$TC_NC" "$TC_WHITE" "$sni_host" "$TC_NC"
    printf '%b%-20s%b %b%s%b\n' "$TC_DARK_GREEN" "PATH WS:" "$TC_NC" "$TC_WHITE" "$path_ws" "$TC_NC"
    printf '%b%-20s%b %b%s (%s días)%b\n' "$TC_DARK_GREEN" "EXPIRA:" "$TC_NC" "$TC_WHITE" "$expiry_date" "$days" "$TC_NC"
    tc_line
    printf '%bENLACE URI (Copiar e importar en v2rayNG / HTTP Custom / Napsternet):%b\n\n' "$TC_YELLOW" "$TC_NC"
    printf '%b%s%b\n\n' "$TC_CYAN" "$uri" "$TC_NC"
    tc_line
    tc_pause
}

# ── Listar Usuarios ───────────────────────────────────────────
tc_v2_list_users() {
    tc_clear
    tc_title "USUARIOS V2RAY REGISTRADOS"

    if [[ ! -f "$TC_V2_REG" || ! -s "$TC_V2_REG" ]]; then
        tc_msg_warn "No hay usuarios registrados."
        tc_pause
        return
    fi

    printf '%b%-16s %-38s %-12s %-8s%b\n' "$TC_YELLOW" "USUARIO" "UUID" "EXPIRA" "PROTO" "$TC_NC"
    tc_line

    local uuid nick exp proto
    while IFS='|' read -r uuid nick exp proto || [[ -n "$uuid" ]]; do
        uuid="$(echo "$uuid" | tr -d ' ')"
        nick="$(echo "$nick" | tr -d ' ')"
        exp="$(echo "$exp" | tr -d ' ')"
        proto="$(echo "$proto" | tr -d ' ')"
        [[ -z "$nick" ]] && continue
        printf '%b%-16s%b %b%-38s%b %b%-12s%b %b%-8s%b\n' \
            "$TC_WHITE" "$nick" "$TC_NC" \
            "$TC_DARK_GREEN" "$uuid" "$TC_NC" \
            "$TC_PALE_GOLD" "$exp" "$TC_NC" \
            "$TC_CYAN" "${proto:-vmess}" "$TC_NC"
    done < "$TC_V2_REG"

    tc_line
    tc_pause
}

# ── Renovar Usuario ───────────────────────────────────────────
tc_v2_renew_user() {
    tc_clear
    tc_title "RENOVAR USUARIO V2RAY"

    if [[ ! -f "$TC_V2_REG" || ! -s "$TC_V2_REG" ]]; then
        tc_msg_warn "No hay usuarios registrados."
        tc_pause
        return
    fi

    local -a users_arr=() uuids_arr=() exps_arr=() protos_arr=()
    local idx=0
    while IFS='|' read -r uuid nick exp proto || [[ -n "$uuid" ]]; do
        uuid="$(echo "$uuid" | tr -d ' ')"
        nick="$(echo "$nick" | tr -d ' ')"
        exp="$(echo "$exp" | tr -d ' ')"
        proto="$(echo "$proto" | tr -d ' ')"
        [[ -z "$nick" ]] && continue
        users_arr+=("$nick")
        uuids_arr+=("$uuid")
        exps_arr+=("$exp")
        protos_arr+=("${proto:-vmess}")
        idx=$((idx + 1))
        tc_opt "$idx" "${nick} (Expira: ${exp})"
    done < "$TC_V2_REG"

    tc_line
    tc_opt "0" "$(_t 'cancel')"
    tc_line
    tc_prompt "Seleccione usuario a renovar"
    read -r sel

    [[ "$sel" == "0" || -z "$sel" ]] && return

    if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#users_arr[@]} )); then
        tc_msg_err "Opción no válida."
        tc_pause
        return
    fi

    local sel_idx=$((sel - 1))
    local sel_user="${users_arr[$sel_idx]}"
    local sel_uuid="${uuids_arr[$sel_idx]}"
    local sel_exp="${exps_arr[$sel_idx]}"
    local sel_proto="${protos_arr[$sel_idx]}"

    printf '\n%bUsuario:%b %b%s%b  %bExpiración actual:%b %b%s%b\n' \
        "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$sel_user" "$TC_NC" \
        "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "$sel_exp" "$TC_NC"

    printf '%bDías a añadir [1-365] (Enter = 30):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r add_d
    [[ -z "$add_d" ]] && add_d="30"

    local new_exp
    new_exp="$(date '+%Y-%m-%d' -d "${sel_exp} +${add_d} days" 2>/dev/null || date '+%Y-%m-%d' -d "+${add_d} days")"

    sed -i "/\|\s*${sel_user}\s*\|/d" "$TC_V2_REG"
    echo "${sel_uuid} | ${sel_user} | ${new_exp} | ${sel_proto}" >> "$TC_V2_REG"

    tc_msg_ok "¡Usuario '$sel_user' renovado hasta el $new_exp!"
    tc_pause
}

# ── Modificar UUID ────────────────────────────────────────────
tc_v2_modify_uuid() {
    local cfg
    cfg="$(tc_v2_config_file)"
    if [[ -z "$cfg" || ! -f "$TC_V2_REG" || ! -s "$TC_V2_REG" ]]; then
        tc_msg_warn "No hay usuarios registrados."
        tc_pause
        return
    fi

    tc_clear
    tc_title "MODIFICAR UUID V2RAY"

    local -a users_arr=() uuids_arr=()
    local idx=0
    while IFS='|' read -r uuid nick exp proto || [[ -n "$uuid" ]]; do
        uuid="$(echo "$uuid" | tr -d ' ')"
        nick="$(echo "$nick" | tr -d ' ')"
        [[ -z "$nick" ]] && continue
        users_arr+=("$nick")
        uuids_arr+=("$uuid")
        idx=$((idx + 1))
        tc_opt "$idx" "${nick} (${uuid})"
    done < "$TC_V2_REG"

    tc_line
    tc_opt "0" "$(_t 'cancel')"
    tc_line
    tc_prompt "Seleccione usuario"
    read -r sel

    [[ "$sel" == "0" || -z "$sel" ]] && return

    if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#users_arr[@]} )); then
        tc_msg_err "Opción no válida."
        tc_pause
        return
    fi

    local sel_idx=$((sel - 1))
    local sel_user="${users_arr[$sel_idx]}"
    local old_uuid="${uuids_arr[$sel_idx]}"

    printf '\n%bUsuario:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$sel_user" "$TC_NC"
    printf '%bUUID Actual:%b %b%s%b\n\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_PALE_GOLD" "$old_uuid" "$TC_NC"

    printf '%bNuevo UUID (Enter para generar automático):%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r new_uuid
    [[ -z "$new_uuid" ]] && new_uuid="$(uuidgen 2>/dev/null || tc_gen_uuid)"

    local tmp="${cfg}.tmp"
    jq --arg old "$old_uuid" --arg new "$new_uuid" '
      .inbounds |= map(
        if ((.settings.clients? | type) == "array") then
          .settings.clients |= map(if .id == $old then .id = $new else . end)
        else
          .
        end
      )
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"

    sed -i "s/${old_uuid}/${new_uuid}/g" "$TC_V2_REG"
    tc_v2_restart

    tc_msg_ok "UUID modificado correctamente."
    printf '%bNuevo UUID:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$new_uuid" "$TC_NC"
    tc_pause
}

# ── Eliminar Usuario ──────────────────────────────────────────
tc_v2_del_user() {
    local cfg
    cfg="$(tc_v2_config_file)"
    if [[ -z "$cfg" || ! -f "$TC_V2_REG" || ! -s "$TC_V2_REG" ]]; then
        tc_msg_warn "No hay usuarios registrados."
        tc_pause
        return
    fi

    tc_clear
    tc_title "ELIMINAR USUARIO V2RAY"

    local -a users_arr=() uuids_arr=()
    local idx=0
    while IFS='|' read -r uuid nick exp proto || [[ -n "$uuid" ]]; do
        uuid="$(echo "$uuid" | tr -d ' ')"
        nick="$(echo "$nick" | tr -d ' ')"
        [[ -z "$nick" ]] && continue
        users_arr+=("$nick")
        uuids_arr+=("$uuid")
        idx=$((idx + 1))
        tc_opt "$idx" "${nick}"
    done < "$TC_V2_REG"

    tc_line
    tc_opt "0" "$(_t 'cancel')"
    tc_line
    tc_prompt "Seleccione usuario a eliminar"
    read -r sel

    [[ "$sel" == "0" || -z "$sel" ]] && return

    if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#users_arr[@]} )); then
        tc_msg_err "Opción no válida."
        tc_pause
        return
    fi

    local sel_idx=$((sel - 1))
    local sel_user="${users_arr[$sel_idx]}"
    local target_uuid="${uuids_arr[$sel_idx]}"

    if ! tc_confirm "¿Eliminar al usuario '$sel_user'?"; then
        return
    fi

    local tmp="${cfg}.tmp"
    jq --arg id "$target_uuid" '
      .inbounds |= map(
        if ((.settings.clients? | type) == "array") then
          .settings.clients |= map(select(.id != $id))
        else
          .
        end
      )
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"

    sed -i "/\|\s*${sel_user}\s*\|/d" "$TC_V2_REG"
    tc_v2_restart

    tc_msg_ok "Usuario '$sel_user' eliminado de V2Ray."
    tc_pause
}

# ── Menú Principal V2Ray Oficial Rufus ────────────────────────
tc_xray_menu() {
    while true; do
        tc_clear
        local cfg
        cfg="$(tc_v2_config_file)"
        tc_title "GESTIÓN DE V2RAY / XRAY $(tc_v2_status_mark)"

        if ! tc_v2_is_installed; then
            tc_opt "1" "INSTALAR V2RAY (OFICIAL MULTI-V2RAY / RUFUS)"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01) tc_v2_install_official ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        else
            local cur_dom
            cur_dom="$(cat "$TC_V2_DOMAIN_FILE" 2>/dev/null || echo "No configurado")"

            printf '%bDOMINIO CDN:%b %b%s%b  %bESTADO:%b %b\n' \
                "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$cur_dom" "$TC_NC" \
                "$TC_DARK_GREEN" "$TC_NC" "$(tc_v2_status_mark)"
            tc_line
            tc_opt "1" "AGREGAR USUARIO (VMESS / VLESS)"
            tc_opt "2" "LISTAR USUARIOS REGISTRADOS"
            tc_opt "3" "RENOVAR DÍAS DE USUARIO"
            tc_opt "4" "MODIFICAR UUID DE USUARIO"
            tc_opt "5" "ELIMINAR USUARIO"
            tc_line
            tc_opt "6" "ABRIR MENÚ COMPLETO MULTI-V2RAY (CONSOLA OFICIAL)"
            tc_opt "7" "CONFIGURAR DOMINIO CDN / HOST"
            tc_opt "8" "REINICIAR SERVICIO V2RAY"
            tc_opt "9" "VER LOGS EN TIEMPO REAL"
            tc_opt "10" "REINSTALAR V2RAY"
            tc_opt "11" "DESINSTALAR V2RAY"
            tc_line
            tc_opt "0" "$(_t 'back')"
            tc_line
            tc_prompt
            read -r opt

            case "$opt" in
                1|01) tc_v2_add_user ;;
                2|02) tc_v2_list_users ;;
                3|03) tc_v2_renew_user ;;
                4|04) tc_v2_modify_uuid ;;
                5|05) tc_v2_del_user ;;
                6|06)
                    if command -v v2ray >/dev/null 2>&1; then
                        v2ray
                    else
                        tc_msg_err "Comando v2ray no encontrado."
                    fi
                    tc_pause
                    ;;
                7|07)
                    printf '%bNuevo Dominio CDN / Host:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r nd
                    if [[ -n "$nd" ]]; then
                        echo "$nd" > "$TC_V2_DOMAIN_FILE"
                        tc_msg_ok "Dominio actualizado a $nd."
                    fi
                    tc_pause
                    ;;
                8|08)
                    tc_v2_restart
                    tc_msg_ok "Servicio V2Ray reiniciado."
                    tc_pause
                    ;;
                9|09)
                    tc_clear
                    tc_title "LOGS V2RAY EN VIVO (Ctrl+C para salir)"
                    journalctl -u v2ray -f --no-pager 2>/dev/null || journalctl -u xray -f --no-pager 2>/dev/null
                    ;;
                10) tc_v2_install_official ;;
                11) tc_v2_uninstall_all ;;
                0|00) break ;;
                *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
            esac
        fi
    done
}
