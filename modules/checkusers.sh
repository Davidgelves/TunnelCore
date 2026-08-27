#!/bin/bash
# TunnelCore - modules/checkusers.sh
# CheckUser propio con flujo de instalacion estilo Rufus.

TC_CHECK_DIR="/root/TunnelCore/checkuser"
TC_CHECK_BIN="${TC_CHECK_DIR}/checkuser_server.py"
TC_CHECK_LOG="${TC_CHECK_DIR}/checkuser.log"
TC_CHECK_CONF="${TC_CHECK_DIR}/checkuser.conf"
TC_CHECK_SERVICE_FILE="/etc/systemd/system/checkuser.service"
TC_CHECK_SERVICE="checkuser"
TC_OLD_CHECK_SERVICE="/etc/systemd/system/tunnelcore-checkuser.service"
TC_OLD_CHECK_DIR="/etc/tunnelcore/checkuser"

tc_checkuser_is_installed() {
    [[ -x "$TC_CHECK_BIN" && -f "$TC_CHECK_SERVICE_FILE" ]]
}

tc_checkuser_is_running() {
    systemctl is-active --quiet "$TC_CHECK_SERVICE" 2>/dev/null
}

tc_checkuser_status_mark() {
    if tc_checkuser_is_running; then
        printf '%bo%b' "$TC_GREEN" "$TC_NC"
    else
        printf '%bx%b' "$TC_RED" "$TC_NC"
    fi
}

tc_checkuser_stop_old_api() {
    systemctl stop tunnelcore-checkuser >/dev/null 2>&1 || true
    systemctl disable tunnelcore-checkuser >/dev/null 2>&1 || true
    rm -f "$TC_OLD_CHECK_SERVICE" 2>/dev/null || true
    rm -rf "$TC_OLD_CHECK_DIR" 2>/dev/null || true
}

tc_checkuser_vps_timezone() {
    local zone
    zone="$(timedatectl show -p Timezone --value 2>/dev/null)"
    [[ -z "$zone" && -f /etc/timezone ]] && zone="$(cat /etc/timezone 2>/dev/null)"
    echo "${zone:-$(date +%Z 2>/dev/null || echo Local)}"
}

tc_checkuser_conf_get() {
    local key="$1" default="$2" value=""
    if [[ -f "$TC_CHECK_CONF" ]]; then
        value="$(grep -E "^${key}=" "$TC_CHECK_CONF" 2>/dev/null | tail -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//')"
    fi
    echo "${value:-$default}"
}

tc_checkuser_current_port() {
    tc_checkuser_conf_get "PORT" "5454"
}

tc_checkuser_write_conf() {
    local port="$1" timezone="$2" date_format="$3"
    mkdir -p "$TC_CHECK_DIR"
    cat > "$TC_CHECK_CONF" <<EOF
PORT="${port}"
TIMEZONE="${timezone}"
DATE_FORMAT="${date_format}"
EOF
}

tc_checkuser_write_server() {
    mkdir -p "$TC_CHECK_DIR"
    cat > "$TC_CHECK_BIN" <<'PYEOF'
#!/usr/bin/env python3
import http.server
import json
import os
import subprocess
import sys
from datetime import datetime
from socketserver import ThreadingTCPServer
from urllib.parse import parse_qs, unquote, urlparse

PORT = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 5454
DB_PATH = "/etc/tunnelcore/users.db"
PASS_DIR = "/etc/tunnelcore/passwords"
CONF_PATH = "/root/TunnelCore/checkuser/checkuser.conf"


def load_config():
    config = {"DATE_FORMAT": "DDMMYY"}
    try:
        with open(CONF_PATH, "r", encoding="utf-8", errors="replace") as data:
            for line in data:
                if "=" not in line:
                    continue
                key, value = line.strip().split("=", 1)
                config[key] = value.strip().strip('"')
    except Exception:
        pass
    return config


def active_connections(user):
    try:
        proc = subprocess.run(["who"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        remotes = set()
        for line in proc.stdout.splitlines():
            cols = line.split()
            if cols and cols[0] == user:
                remote = cols[-1].strip("()")
                if remote:
                    remotes.add(remote)
        if remotes:
            return len(remotes)
    except Exception:
        pass

    total = 0
    try:
        proc = subprocess.run(["ps", "-o", "user=", "-C", "sshd"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        total += sum(1 for line in proc.stdout.splitlines() if line.strip() == user)
    except Exception:
        pass

    try:
        proc = subprocess.run(["ps", "-u", user, "-o", "comm="], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        total += sum(1 for line in proc.stdout.splitlines() if line.strip() == "dropbear")
    except Exception:
        pass

    return total


def user_password(user):
    path = os.path.join(PASS_DIR, user)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as data:
            return data.read().strip()
    except Exception:
        return ""


def format_date(exp, date_format):
    if date_format == "DD-MM-YY":
        return exp.strftime("%d-%m-%y")
    return exp.strftime("%d%m%y")


def expiration_info(raw, date_format):
    now = datetime.now()
    if raw.startswith("test:"):
        try:
            _, ts, _minutes = raw.split(":", 2)
            left = int(ts) - int(now.timestamp())
            mins = max(0, (left + 59) // 60)
            return raw, f"{mins} Minutos", 0, left > 0
        except Exception:
            return raw, raw, 0, True

    try:
        exp = datetime.strptime(raw, "%Y-%m-%d")
        days = max(0, (exp - now).days + 1)
        return raw, format_date(exp, date_format), days, days > 0
    except Exception:
        return raw, raw, 0, True


def load_users():
    users = []
    config = load_config()
    date_format = config.get("DATE_FORMAT", "DDMMYY")
    if not os.path.isfile(DB_PATH):
        return users

    with open(DB_PATH, "r", encoding="utf-8", errors="replace") as db:
        for line in db:
            parts = [part.strip() for part in line.split("|")]
            if len(parts) < 3 or not parts[0]:
                continue
            user, expiry, limit = parts[0], parts[1], parts[2]
            exp_raw, exp_label, exp_days, is_active = expiration_info(expiry, date_format)
            conns = active_connections(user)
            lim = int(limit) if limit.isdigit() else 1
            users.append({
                "username": user,
                "user": user,
                "password": user_password(user),
                "count_connection": conns,
                "online": conns,
                "limit_connection": lim,
                "limit": lim,
                "expiration_date": exp_raw,
                "expiration": exp_label,
                "expiration_days": exp_days,
                "is_active": is_active,
                "status": "active" if is_active else "expired",
            })
    return users


class CheckUserHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.strip("/")
        params = parse_qs(parsed.query)
        user = params.get("user", [""])[0] or params.get("usuario", [""])[0]

        if not user and path.lower().startswith("checkuser/"):
            user = path.split("/", 1)[1]
        elif not user and path and path.lower() not in ("checkuser", "online", "onlines"):
            user = path

        user = unquote(user).strip()
        users = load_users()

        if path.lower() == "checkuser" and not user:
            self.respond_text(200, "")
            return

        if user:
            for item in users:
                if item["username"] == user:
                    self.respond(200, item)
                    return
            self.respond(404, {"error": "User not found"})
            return

        online = [item for item in users if item["online"] > 0]
        self.respond(200, {
            "server": "TunnelCore",
            "total_users": len(users),
            "online_users": len(online),
            "total_connections": sum(item["online"] for item in users),
            "users": online if path.lower() in ("", "online", "onlines") else users,
        })

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        raw_body = self.rfile.read(length).decode("utf-8", errors="replace") if length > 0 else ""
        user = ""

        try:
            data = json.loads(raw_body) if raw_body else {}
            user = str(data.get("user") or data.get("usuario") or "").strip()
        except Exception:
            params = parse_qs(raw_body)
            user = (params.get("user", [""])[0] or params.get("usuario", [""])[0]).strip()

        user = unquote(user).strip()
        if not user:
            self.respond_text(200, "not exist")
            return

        for item in load_users():
            if item["username"] == user and item["is_active"]:
                self.respond(200, item)
                return

        self.respond_text(200, "not exist")

    def respond(self, code, data):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def respond_text(self, code, text):
        body = text.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stdout.write("%s - %s\n" % (self.address_string(), fmt % args))
        sys.stdout.flush()


def main():
    ThreadingTCPServer.allow_reuse_address = True
    with ThreadingTCPServer(("0.0.0.0", PORT), CheckUserHandler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
PYEOF
    chmod +x "$TC_CHECK_BIN"
}

tc_checkuser_write_service() {
    local port="$1" timezone="$2"
    cat > "$TC_CHECK_SERVICE_FILE" <<EOF
[Unit]
Description=TunnelCore CheckUser Online
After=network.target

[Service]
User=root
WorkingDirectory=${TC_CHECK_DIR}
Environment=TZ=${timezone}
ExecStart=/usr/bin/python3 ${TC_CHECK_BIN} ${port}
StandardOutput=append:${TC_CHECK_LOG}
StandardError=append:${TC_CHECK_LOG}
Restart=always
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF
}

tc_checkuser_select_timezone() {
    local vps_zone opt
    vps_zone="$(tc_checkuser_vps_timezone)"
    while true; do
        tc_clear
        tc_title "CONFIGURACION DE CHECKUSER - ONLINE"
        tc_opt "1" "UTC (HORA INTERNACIONAL)"
        tc_opt "2" "ZONA HORARIA (${vps_zone})"
        tc_opt "0" "VOLVER"
        tc_line
        tc_prompt
        read -r opt
        case "$opt" in
            1|01) TC_CHECKUSER_SELECTED_TIMEZONE="UTC"; return 0 ;;
            2|02) TC_CHECKUSER_SELECTED_TIMEZONE="$vps_zone"; return 0 ;;
            0|00) return 1 ;;
            *) tc_msg_err "Opcion no valida."; sleep 1 ;;
        esac
    done
}

tc_checkuser_select_date_format() {
    local port="$1" timezone="$2" opt
    while true; do
        tc_clear
        tc_title "CONFIGURACION DE CHECKUSER - ONLINE"
        printf '%bPUERTO:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$port" "$TC_NC"
        printf '%bZONA HORARIA:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$timezone" "$TC_NC"
        printf '%b------------------------------------------------------------%b\n' "$TC_WHITE" "$TC_NC"
        printf '%bFORMATO DE FECHA...%b\n' "$TC_YELLOW" "$TC_NC"
        tc_opt "1" "DDMMYY"
        tc_opt "2" "(DD-MM-YY)"
        tc_line
        printf '%bFORMATO:%b ' "$TC_CYAN" "$TC_NC"
        read -r opt
        case "$opt" in
            1|01) TC_CHECKUSER_SELECTED_DATE_FORMAT="DDMMYY"; return 0 ;;
            2|02) TC_CHECKUSER_SELECTED_DATE_FORMAT="DD-MM-YY"; return 0 ;;
            *) tc_msg_err "Opcion no valida."; sleep 1 ;;
        esac
    done
}

tc_checkuser_apply_screen() {
    local port="$1" timezone="$2" date_format="$3" opt
    while true; do
        tc_clear
        tc_title "CONFIGURACION DE CHECKUSER - ONLINE"
        printf '%bPUERTO:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$port" "$TC_NC"
        printf '%bZONA HORARIA:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$timezone" "$TC_NC"
        printf '%bFORMATO DE FECHA:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$date_format" "$TC_NC"
        printf '%b------------------------%b\n' "$TC_WHITE" "$TC_NC"
        tc_opt "1" "APLICAR"
        tc_opt "2" "CANCELAR"
        tc_line
        tc_prompt
        read -r opt
        case "$opt" in
            1|01) return 0 ;;
            2|02|0|00) return 1 ;;
            *) tc_msg_err "Opcion no valida."; sleep 1 ;;
        esac
    done
}

tc_checkuser_install_wizard() {
    local port timezone date_format
    tc_checkuser_stop_old_api
    tc_clear
    tc_title "CHECKUSER - ONLINE"
    printf '%bINGRESA PUERTO [ENTER: 5454]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r port
    [[ -z "$port" ]] && port="5454"

    if ! tc_valid_port "$port"; then
        tc_msg_err "Puerto no valido."
        tc_pause
        return
    fi
    if tc_port_in_use "$port" && ! tc_checkuser_is_running; then
        tc_msg_err "El puerto $port ya esta siendo usado por otro servicio."
        tc_pause
        return
    fi

    tc_checkuser_select_timezone || return
    timezone="$TC_CHECKUSER_SELECTED_TIMEZONE"
    tc_checkuser_select_date_format "$port" "$timezone" || return
    date_format="$TC_CHECKUSER_SELECTED_DATE_FORMAT"
    tc_checkuser_apply_screen "$port" "$timezone" "$date_format" || return

    tc_clear
    tc_title "CONFIGURACION DE CHECKUSER - ONLINE"
    printf '%bPUERTO:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$port" "$TC_NC"
    printf '%bZONA HORARIA:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$timezone" "$TC_NC"
    printf '%bFORMATO DE FECHA:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$date_format" "$TC_NC"
    printf '%b------------------------%b\n' "$TC_WHITE" "$TC_NC"

    tc_require_cmd "python3" "python3"
    tc_checkuser_write_conf "$port" "$timezone" "$date_format"
    tc_checkuser_write_server
    tc_checkuser_write_service "$port" "$timezone"

    systemctl daemon-reload >/dev/null 2>&1 && printf '       systemctl daemon-reload............%bOK%b\n' "$TC_GREEN" "$TC_NC" || printf '       systemctl daemon-reload............%bERROR%b\n' "$TC_RED" "$TC_NC"
    systemctl enable "$TC_CHECK_SERVICE" >/dev/null 2>&1 || true
    systemctl restart "$TC_CHECK_SERVICE" >/dev/null 2>&1 && printf '       systemctl start checkuser..........%bOK%b\n' "$TC_GREEN" "$TC_NC" || printf '       systemctl start checkuser..........%bERROR%b\n' "$TC_RED" "$TC_NC"

    tc_line
    printf '%b>>>> ENTER PARA CONTINUAR <<<<<%b' "$TC_YELLOW" "$TC_NC"
    read -r _
}

tc_checkuser_uninstall() {
    systemctl stop "$TC_CHECK_SERVICE" >/dev/null 2>&1 || true
    systemctl disable "$TC_CHECK_SERVICE" >/dev/null 2>&1 || true
    rm -f "$TC_CHECK_SERVICE_FILE" 2>/dev/null || true
    rm -rf "$TC_CHECK_DIR" 2>/dev/null || true
    systemctl daemon-reload >/dev/null 2>&1 || true
}

tc_checkuser_installed_menu() {
    local ip port opt
    while true; do
        tc_clear
        ip="$(tc_public_ip)"
        port="$(tc_checkuser_current_port)"
        tc_title "CHECKUSER - ONLINE"
        printf '%bURL CHECKUSER:%b %bhttp://%s:%s/checkuser%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$ip" "$port" "$TC_NC"
        printf '%bURL ONLINES:  %b %bhttp://%s:%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$ip" "$port" "$TC_NC"
        printf '%b-------------------------------------------------------------------------%b\n' "$TC_WHITE" "$TC_NC"
        tc_opt "1" "ESTADO DE SERVICIO"
        tc_opt "2" "REINICIAR SERVICIO"
        tc_opt "3" "INICIAR/PARAR CHECKUSER" " $(tc_checkuser_status_mark)"
        tc_opt "4" "LOG CHECKUSER"
        tc_opt "5" "DESINSTALAR"
        tc_opt "0" "VOLVER"
        tc_line
        tc_prompt
        read -r opt

        case "$opt" in
            1|01)
                tc_clear
                tc_title "ESTADO DEL SERVICIO"
                systemctl status "$TC_CHECK_SERVICE" --no-pager 2>/dev/null || tc_msg_warn "CheckUser no esta instalado."
                tc_pause
                ;;
            2|02)
                systemctl restart "$TC_CHECK_SERVICE" >/dev/null 2>&1
                tc_msg_ok "CheckUser reiniciado."
                tc_pause
                ;;
            3|03)
                if tc_checkuser_is_running; then
                    systemctl stop "$TC_CHECK_SERVICE" >/dev/null 2>&1
                    tc_msg_ok "CheckUser detenido."
                else
                    systemctl start "$TC_CHECK_SERVICE" >/dev/null 2>&1
                    tc_msg_ok "CheckUser iniciado."
                fi
                tc_pause
                ;;
            4|04)
                tc_clear
                tc_title "LOG CHECKUSER"
                if [[ -f "$TC_CHECK_LOG" ]]; then
                    tail -n 100 "$TC_CHECK_LOG"
                else
                    tc_msg_warn "No hay log disponible."
                fi
                tc_pause
                ;;
            5|05)
                printf '%bConfirma que quiere desinstalar CheckUser? [S/N]:%b ' "$TC_YELLOW" "$TC_NC"
                read -r confirm
                if [[ "$confirm" =~ ^[sS]$ ]]; then
                    tc_checkuser_uninstall
                    tc_msg_ok "CheckUser desinstalado."
                    tc_pause
                    return
                fi
                tc_msg_warn "Operacion cancelada."
                tc_pause
                ;;
            0|00) return ;;
            *) tc_msg_err "Opcion no valida."; sleep 1 ;;
        esac
    done
}

tc_checkuser_menu() {
    local opt
    while true; do
        if tc_checkuser_is_installed; then
            tc_checkuser_installed_menu
            return
        fi

        tc_clear
        tc_title "CHECKUSER - ONLINE"
        tc_opt "1" "INSTALAR CHECKUSER"
        tc_opt "0" "VOLVER"
        tc_line
        tc_prompt
        read -r opt
        case "$opt" in
            1|01) tc_checkuser_install_wizard ;;
            0|00) return ;;
            *) tc_msg_err "Opcion no valida."; sleep 1 ;;
        esac
    done
}
