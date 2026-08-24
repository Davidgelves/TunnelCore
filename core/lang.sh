#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — core/lang.sh
#  Sistema de Internacionalización (i18n) Bilingüe (Español / English)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════

# Variable global de idioma (por defecto español si no está seteado)
TC_LANG="${TC_LANG:-es}"

# ── Función principal de traducción ───────────────────────────
tc_tr() {
    local key="$1"
    local lang="${TC_LANG:-es}"

    if [[ "$lang" == "en" ]]; then
        case "$key" in
            # Header
            "system")              echo "SYSTEM" ;;
            "ram")                 echo "RAM MEMORY" ;;
            "processor")           echo "PROCESSOR" ;;
            "time")                echo "Time" ;;
            "cores")               echo "Cores" ;;
            "total")               echo "Total" ;;
            "connected")           echo "Connected" ;;
            "expired")             echo "Expired" ;;
            "users_total")         echo "Total" ;;
            
            # Menú Principal
            "menu_users")          echo "MANAGE USERS" ;;
            "menu_protocols")      echo "PROTOCOL CONFIGURATION" ;;
            "menu_banner")         echo "BANNER CONFIGURATION" ;;
            "menu_limiter")        echo "CONNECTION LIMITER" ;;
            "menu_checkusers")     echo "CHECKUSERS" ;;
            "menu_network")        echo "NETWORK & SECURITY" ;;
            "menu_vps")            echo "VPS CONFIGURATION" ;;
            "menu_settings")       echo "SCRIPT SETTINGS" ;;
            "menu_extras")         echo "MORE SETTINGS >>>" ;;
            "menu_reboot")         echo "REBOOT VPS" ;;
            "option")              echo "Option" ;;
            "back")                echo "BACK" ;;
            "cancel")              echo "CANCEL" ;;
            "confirm")             echo "Confirm" ;;
            "press_enter")         echo "Press Enter to continue" ;;
            "invalid_option")      echo "Invalid option." ;;
            "goodbye")             echo "Goodbye." ;;
            "reboot_confirm")      echo "Reboot the VPS now?" ;;

            # Estado
            "enabled")             echo "ENABLED" ;;
            "disabled")            echo "DISABLED" ;;
            "installed")           echo "INSTALLED" ;;
            "not_installed")       echo "NOT INSTALLED" ;;

            # Gestión de Usuarios
            "users_title")         echo "MANAGE USERS" ;;
            "user_create")         echo "CREATE USER" ;;
            "user_remove")         echo "REMOVE USER" ;;
            "user_renew")          echo "RENEW / CHANGE EXPIRY" ;;
            "user_change_pass")    echo "CHANGE PASSWORD" ;;
            "user_change_limit")   echo "CHANGE CONNECTION LIMIT" ;;
            "user_list")           echo "LIST USERS" ;;
            "user_cleanup")        echo "CLEAN EXPIRED USERS" ;;
            "user_prompt_name")    echo "Username (2-20 characters):" ;;
            "user_prompt_pass")    echo "Password (Enter to generate random):" ;;
            "user_prompt_days")    echo "Duration in days [1-365]:" ;;
            "user_prompt_limit")   echo "Max simultaneous connections [1-99] (Enter = 1):" ;;
            "user_created_success") echo "USER CREATED SUCCESSFULLY" ;;
            "user_ip_host")        echo "IP / HOST:" ;;
            "user_username")       echo "USERNAME:" ;;
            "user_password")       echo "PASSWORD:" ;;
            "user_expires")        echo "EXPIRES ON:" ;;
            "user_limit")          echo "CONNECTION LIMIT:" ;;
            "user_days")           echo "days" ;;
            "user_empty_err")      echo "Username cannot be empty." ;;
            "user_format_err")     echo "Only letters, numbers, dashes (-) and underscores (_) allowed (2-20 chars)." ;;
            "user_exists_err")     echo "User already exists." ;;
            "user_none_registered") echo "No registered users found." ;;
            "user_delete_confirm") echo "Are you sure you want to delete user" ;;

            # Protocolos
            "proto_title")         echo "PROTOCOL CONFIGURATION" ;;
            "proto_v2ray")         echo "V2RAY / XRAY" ;;
            "proto_slowdns")       echo "SLOWDNS (DNSTT)" ;;
            "proto_hysteria")      echo "HYSTERIA UDP" ;;
            "proto_proxy")         echo "SOCKS PROXY" ;;
            "proto_ws")            echo "WEBSOCKET SSH" ;;
            "proto_badvpn")        echo "BADVPN (UDPGW)" ;;
            "proto_stunnel")       echo "STUNNEL (SSL)" ;;
            "proto_squid")         echo "SQUID PROXY" ;;
            "proto_dropbear")      echo "DROPBEAR SSH" ;;
            "proto_install")       echo "INSTALL" ;;
            "proto_reconfigure")   echo "RECONFIGURE" ;;
            "proto_restart")       echo "RESTART SERVICE" ;;
            "proto_logs")          echo "VIEW LOGS" ;;
            "proto_uninstall")     echo "UNINSTALL" ;;

            # Configuración & Lenguaje
            "settings_title")      echo "SCRIPT SETTINGS" ;;
            "settings_update")     echo "UPDATE TUNNELCORE" ;;
            "settings_backup")     echo "CREATE USER BACKUP" ;;
            "settings_restore")    echo "RESTORE USER BACKUP" ;;
            "settings_view")       echo "VIEW CURRENT CONFIG" ;;
            "settings_lang")       echo "CHANGE LANGUAGE / CAMBIAR IDIOMA" ;;
            "lang_selected_en")    echo "Language set to English." ;;
            "lang_selected_es")    echo "Idioma cambiado a Español." ;;

            *) echo "$key" ;;
        esac
    else
        # Español (Default)
        case "$key" in
            # Header
            "system")              echo "SISTEMA" ;;
            "ram")                 echo "MEMORIA RAM" ;;
            "processor")           echo "PROCESADOR" ;;
            "time")                echo "Hora" ;;
            "cores")               echo "Nucleos" ;;
            "total")               echo "Total" ;;
            "connected")           echo "Conectados" ;;
            "expired")             echo "Caducados" ;;
            "users_total")         echo "Total" ;;

            # Menú Principal
            "menu_users")          echo "ADMINISTRAR USUARIOS" ;;
            "menu_protocols")      echo "CONFIGURACION DE PROTOCOLOS" ;;
            "menu_banner")         echo "CONFIGURACION DE BANNER" ;;
            "menu_limiter")        echo "ACTIVAR LIMITADOR" ;;
            "menu_checkusers")     echo "CHECKUSERS" ;;
            "menu_network")        echo "RED Y SEGURIDAD" ;;
            "menu_vps")            echo "CONFIGURACION DE LA VPS" ;;
            "menu_settings")       echo "CONFIGURACION DEL SCRIPT" ;;
            "menu_extras")         echo "MAS AJUSTES >>>" ;;
            "menu_reboot")         echo "REINICIAR VPS" ;;
            "option")              echo "Opcion" ;;
            "back")                echo "VOLVER" ;;
            "cancel")              echo "CANCELAR" ;;
            "confirm")             echo "Confirmar" ;;
            "press_enter")         echo "Enter para continuar" ;;
            "invalid_option")      echo "Opción no válida." ;;
            "goodbye")             echo "Hasta luego." ;;
            "reboot_confirm")      echo "¿Reiniciar la VPS ahora?" ;;

            # Estado
            "enabled")             echo "ACTIVADO" ;;
            "disabled")            echo "DESACTIVADO" ;;
            "installed")           echo "INSTALADO" ;;
            "not_installed")       echo "NO INSTALADO" ;;

            # Gestión de Usuarios
            "users_title")         echo "ADMINISTRAR USUARIOS" ;;
            "user_create")         echo "CREAR USUARIO" ;;
            "user_remove")         echo "ELIMINAR USUARIO" ;;
            "user_renew")          echo "RENOVAR / CAMBIAR EXPIRACIÓN" ;;
            "user_change_pass")    echo "CAMBIAR CONTRASEÑA" ;;
            "user_change_limit")   echo "CAMBIAR LÍMITE DE CONEXIONES" ;;
            "user_list")           echo "LISTAR USUARIOS" ;;
            "user_cleanup")        echo "LIMPIAR USUARIOS EXPIRADOS" ;;
            "user_prompt_name")    echo "Nombre de usuario (2-20 carácteres):" ;;
            "user_prompt_pass")    echo "Contraseña (Enter para generar aleatoria):" ;;
            "user_prompt_days")    echo "Duración en días [1-365]:" ;;
            "user_prompt_limit")   echo "Límite de conexiones simultáneas [1-99] (Enter = 1):" ;;
            "user_created_success") echo "USUARIO CREADO CON ÉXITO" ;;
            "user_ip_host")        echo "IP / HOST:" ;;
            "user_username")       echo "USUARIO:" ;;
            "user_password")       echo "CONTRASEÑA:" ;;
            "user_expires")        echo "EXPIRA EL:" ;;
            "user_limit")          echo "LÍMITE CONEXIONES:" ;;
            "user_days")           echo "días" ;;
            "user_empty_err")      echo "El nombre de usuario no puede estar vacío." ;;
            "user_format_err")     echo "Solo se permiten letras, números, guiones (-) y (_, 2 a 20 carácteres)." ;;
            "user_exists_err")     echo "El usuario ya existe en el sistema." ;;
            "user_none_registered") echo "No hay usuarios registrados en TunnelCore." ;;
            "user_delete_confirm") echo "¿Está seguro de eliminar al usuario" ;;

            # Protocolos
            "proto_title")         echo "CONFIGURACION DE PROTOCOLOS" ;;
            "proto_v2ray")         echo "V2RAY / XRAY" ;;
            "proto_slowdns")       echo "SLOWDNS (DNSTT)" ;;
            "proto_hysteria")      echo "HYSTERIA UDP" ;;
            "proto_proxy")         echo "PROXY SOCKS" ;;
            "proto_ws")            echo "WEBSOCKET SSH" ;;
            "proto_badvpn")        echo "BADVPN (UDPGW)" ;;
            "proto_stunnel")       echo "STUNNEL (SSL)" ;;
            "proto_squid")         echo "SQUID PROXY" ;;
            "proto_dropbear")      echo "DROPBEAR SSH" ;;
            "proto_install")       echo "INSTALAR" ;;
            "proto_reconfigure")   echo "RECONFIGURAR" ;;
            "proto_restart")       echo "REINICIAR SERVICIO" ;;
            "proto_logs")          echo "VER LOGS" ;;
            "proto_uninstall")     echo "DESINSTALAR" ;;

            # Configuración & Lenguaje
            "settings_title")      echo "CONFIGURACIÓN DEL SCRIPT" ;;
            "settings_update")     echo "ACTUALIZAR TUNNELCORE" ;;
            "settings_backup")     echo "CREAR COPIA DE SEGURIDAD (BACKUP)" ;;
            "settings_restore")    echo "RESTAURAR COPIA DE SEGURIDAD" ;;
            "settings_view")       echo "VER CONFIGURACIÓN ACTUAL" ;;
            "settings_lang")       echo "CAMBIAR IDIOMA / CHANGE LANGUAGE" ;;
            "lang_selected_en")    echo "Language set to English." ;;
            "lang_selected_es")    echo "Idioma cambiado a Español." ;;

            *) echo "$key" ;;
        esac
    fi
}

# Alias corto
_t() {
    tc_tr "$@"
}

# ── Selector Interactivo de Idioma ────────────────────────────
tc_lang_select() {
    tc_clear
    tc_title "$(_t 'settings_lang')"
    tc_opt "1" "Español" "$([[ "${TC_LANG:-es}" == "es" ]] && printf '%b[ACTIVO]%b' "$TC_GREEN" "$TC_NC" || echo '')"
    tc_opt "2" "English" "$([[ "${TC_LANG:-es}" == "en" ]] && printf '%b[ACTIVE]%b' "$TC_GREEN" "$TC_NC" || echo '')"
    tc_line
    tc_opt "0" "$(_t 'back')"
    tc_line
    tc_prompt "$(_t 'option')"
    read -r l_opt

    case "$l_opt" in
        1)
            TC_LANG="es"
            tc_config_set "TC_LANG" "es"
            tc_msg_ok "$(_t 'lang_selected_es')"
            tc_pause
            ;;
        2)
            TC_LANG="en"
            tc_config_set "TC_LANG" "en"
            tc_msg_ok "$(_t 'lang_selected_en')"
            tc_pause
            ;;
        0) return ;;
        *) tc_msg_err "$(_t 'invalid_option')"; sleep 1 ;;
    esac
}

