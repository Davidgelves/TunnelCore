#!/bin/bash
# TunnelCore - modules/checkusers.sh
# API CheckUser compatible para aplicaciones VPN Android.

TC_CHECK_DIR="/etc/tunnelcore/checkuser"
TC_CHECK_PY="${TC_CHECK_DIR}/checkuser_server.py"
TC_CHECK_SERVICE="/etc/systemd/system/tunnelcore-checkuser.service"
TC_CHECK_CONF="${TC_CHECK_DIR}/checkuser.conf"

tc_checkuser_is_running() {
    systemctl is-active --quiet tunnelcore-checkuser 2>/dev/null
}

tc_checkuser_status_mark() {
    if tc_checkuser_is_running; then
        printf '%bo%b' "$TC_GREEN" "$TC_NC"
    else
        printf '%bx%b' "$TC_RED" "$TC_NC"
    fi
}

tc_checkuser_current_port() {
    local cur_port="5000"
    if [[ -f "$TC_CHECK_CONF" ]]; then
        cur_port="$(grep -oE '[0-9]+' "$TC_CHECK_CONF" | head -1 || echo "5000")"
    fi
    echo "${cur_port:-5000}"
}

tc_checkuser_write_server() {
    mkdir -p "$TC_CHECK_DIR"
    cat > "$TC_CHECK_PY" <<'PYEOF'
#!/usr/bin/env python3
import http.server
import json
import os
import socketserver
import subprocess
import sys
from datetime import datetime
from urllib.parse import parse_qs, unquote, urlparse

PORT = 5000
if len(sys.argv) > 1:
    try:
        PORT = int(sys.argv[1])
    except ValueError:
        pass

DB_PATH = "/etc/tunnelcore/users.db"


class CheckUserHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.strip("/")
        user = ""

        if parsed.query:
            params = parse_qs(parsed.query)
            user = params.get("user", [""])[0] or params.get("usuario", [""])[0]

        if not user and "/" in path:
            user = path.split("/", 1)[1]
        elif not user and path and path != "checkUser":
            user = path

        user = unquote(user).strip()
        if not user:
            self._respond(400, {"error": "Missing user parameter"})
            return

        data = self._get_user_info(user)
        if data:
            self._respond(200, data)
        else:
            self._respond(404, {"error": "User not found"})

    def _get_user_info(self, user):
        if not os.path.isfile(DB_PATH):
            return None

        today = datetime.now()
        with open(DB_PATH, "r", encoding="utf-8", errors="replace") as db:
            for line in db:
                parts = [part.strip() for part in line.split("|")]
                if len(parts) < 3 or parts[0] != user:
                    continue

                expiry_str = parts[1]
                limit_str = parts[2]
                limit_connection = int(limit_str) if limit_str.isdigit() else 1
                active_connections = self._active_connections(user)
                expiration_label = expiry_str
                expiration_days = 0
                is_expired = False

                if expiry_str.startswith("test:"):
                    try:
                        _, ts, _minutes = expiry_str.split(":", 2)
                        left = int(ts) - int(datetime.now().timestamp())
                        is_expired = left <= 0
                        mins_left = max(0, (left + 59) // 60)
                        expiration_label = f"{mins_left} Minutos"
                    except Exception:
                        pass
                else:
                    try:
                        exp_dt = datetime.strptime(expiry_str, "%Y-%m-%d")
                        diff = (exp_dt - today).days + 1
                        expiration_days = max(0, diff)
                        is_expired = diff <= 0
                    except Exception:
                        pass

                return {
                    "username": user,
                    "user": user,
                    "count_connection": active_connections,
                    "online": active_connections,
                    "limit_connection": limit_connection,
                    "limit": limit_connection,
                    "expiration_date": expiry_str,
                    "expiration": expiration_label,
                    "expiration_days": expiration_days,
                    "is_active": not is_expired,
                    "status": "active" if not is_expired else "expired",
                }
        return None

    def _active_connections(self, user):
        try:
            who = subprocess.run(["who"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            seen = set()
            for line in who.stdout.splitlines():
                cols = line.split()
                if cols and cols[0] == user:
                    remote = cols[-1].strip("()")
                    if remote:
                        seen.add(remote)
            if seen:
                return len(seen)
        except Exception:
            pass

        total = 0
        try:
            sshd = subprocess.run(["ps", "-o", "user=", "-C", "sshd"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            total += sum(1 for line in sshd.stdout.splitlines() if line.strip() == user)
        except Exception:
            pass

        try:
            psu = subprocess.run(["ps", "-u", user, "-o", "comm="], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            total += sum(1 for line in psu.stdout.splitlines() if line.strip() == "dropbear")
        except Exception:
            pass

        return total

    def _respond(self, code, data):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format, *args):
        return


def main():
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("0.0.0.0", PORT), CheckUserHandler) as httpd:
        httpd.serve_forever()


if __name__ == "__main__":
    main()
PYEOF
    chmod +x "$TC_CHECK_PY"
}

tc_checkuser_start() {
    local port="${1:-5000}"
    mkdir -p "$TC_CHECK_DIR"
    tc_require_cmd "python3" "python3"
    tc_checkuser_write_server

    cat > "$TC_CHECK_CONF" <<EOF
CHECKUSER_PORT="${port}"
EOF

    cat > "$TC_CHECK_SERVICE" <<EOF
[Unit]
Description=TunnelCore CheckUser API Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${TC_CHECK_PY} ${port}
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable tunnelcore-checkuser >/dev/null 2>&1
    systemctl restart tunnelcore-checkuser >/dev/null 2>&1
}

tc_checkuser_stop() {
    systemctl stop tunnelcore-checkuser >/dev/null 2>&1 || true
    systemctl disable tunnelcore-checkuser >/dev/null 2>&1 || true
}

tc_checkuser_uninstall() {
    tc_checkuser_stop
    rm -f "$TC_CHECK_SERVICE"
    rm -rf "$TC_CHECK_DIR"
    systemctl daemon-reload >/dev/null 2>&1 || true
}

tc_checkuser_install_prompt() {
    local port
    printf '%bPuerto CheckUser [Enter = 5000]:%b ' "$TC_DARK_GREEN" "$TC_NC"
    read -r port
    [[ -z "$port" ]] && port="5000"

    if ! tc_valid_port "$port"; then
        tc_msg_err "Puerto no valido."
        tc_pause
        return
    fi

    if tc_port_in_use "$port" && [[ "$(tc_checkuser_current_port)" != "$port" ]]; then
        tc_msg_err "El puerto $port ya esta siendo usado por otro servicio."
        tc_pause
        return
    fi

    tc_checkuser_start "$port"
    if tc_checkuser_is_running; then
        tc_msg_ok "CheckUser instalado y activo en puerto $port."
    else
        tc_msg_err "Error al iniciar CheckUser."
    fi
    tc_pause
}

tc_checkuser_menu() {
    while true; do
        tc_clear
        local cur_port ip
        cur_port="$(tc_checkuser_current_port)"
        ip="$(tc_public_ip)"

        tc_title "VERIFICACION CHECKUSER $(tc_checkuser_status_mark)"
        if [[ -f "$TC_CHECK_CONF" ]]; then
            printf '%bPUERTO:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$cur_port" "$TC_NC"
            printf '%bURL API:%b %bhttp://%s:%s/checkUser?user=USUARIO%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$ip" "$cur_port" "$TC_NC"
            tc_line
        fi

        tc_opt "1" "INSTALAR CHECKUSER"
        tc_opt "2" "ESTADO DEL SERVICIO"
        tc_opt "3" "REINICIAR SERVICIO"
        tc_opt "4" "INICIAR/PARAR CHECKUSER"
        tc_opt "5" "LOG CHECKUSER"
        tc_opt "6" "LOG EN TIEMPO REAL"
        tc_opt "7" "LIMPIAR LOG"
        tc_opt "8" "DESINSTALAR CHECKUSER"
        tc_line
        tc_opt "0" "VOLVER"
        tc_line
        tc_prompt
        read -r opt

        case "$opt" in
            1|01) tc_checkuser_install_prompt ;;
            2|02)
                tc_clear
                tc_title "ESTADO DEL SERVICIO"
                systemctl status tunnelcore-checkuser --no-pager 2>/dev/null || tc_msg_warn "CheckUser no esta instalado."
                tc_pause
                ;;
            3|03)
                if [[ -f "$TC_CHECK_CONF" ]]; then
                    systemctl restart tunnelcore-checkuser >/dev/null 2>&1
                    tc_msg_ok "CheckUser reiniciado."
                else
                    tc_msg_warn "Primero instale CheckUser."
                fi
                tc_pause
                ;;
            4|04)
                if tc_checkuser_is_running; then
                    tc_checkuser_stop
                    tc_msg_ok "CheckUser detenido."
                elif [[ -f "$TC_CHECK_CONF" ]]; then
                    tc_checkuser_start "$cur_port"
                    tc_msg_ok "CheckUser iniciado."
                else
                    tc_msg_warn "Primero instale CheckUser."
                fi
                tc_pause
                ;;
            5|05)
                tc_clear
                tc_title "LOG CHECKUSER"
                journalctl -u tunnelcore-checkuser -n 80 --no-pager 2>/dev/null || tc_msg_warn "No hay logs disponibles."
                tc_pause
                ;;
            6|06)
                tc_clear
                tc_title "LOG EN TIEMPO REAL"
                journalctl -fu tunnelcore-checkuser 2>/dev/null
                tc_pause
                ;;
            7|07)
                journalctl --rotate >/dev/null 2>&1 || true
                journalctl --vacuum-time=1s >/dev/null 2>&1 || true
                tc_msg_ok "Log CheckUser limpiado."
                tc_pause
                ;;
            8|08)
                printf '%bConfirma que quiere desinstalar CheckUser? [S/N]:%b ' "$TC_YELLOW" "$TC_NC"
                read -r confirm
                if [[ "$confirm" =~ ^[sS]$ ]]; then
                    tc_checkuser_uninstall
                    tc_msg_ok "CheckUser desinstalado."
                else
                    tc_msg_warn "Operacion cancelada."
                fi
                tc_pause
                ;;
            0|00) break ;;
            *) tc_msg_err "Opcion no valida."; sleep 1 ;;
        esac
    done
}
