#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — modules/checkusers.sh
#  API CheckUser para aplicaciones VPN Android (HTTP JSON)
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════

TC_CHECK_DIR="/etc/tunnelcore/checkuser"
TC_CHECK_PY="${TC_CHECK_DIR}/checkuser_server.py"
TC_CHECK_SERVICE="/etc/systemd/system/tunnelcore-checkuser.service"
TC_CHECK_CONF="${TC_CHECK_DIR}/checkuser.conf"

tc_checkuser_is_running() {
    systemctl is-active --quiet tunnelcore-checkuser 2>/dev/null
}

tc_checkuser_status_mark() {
    if tc_checkuser_is_running; then
        printf '%b[ON]%b' "$TC_GREEN" "$TC_NC"
    elif [[ -f "$TC_CHECK_CONF" ]]; then
        printf '%b[OFF]%b' "$TC_RED" "$TC_NC"
    else
        printf '%b[NO INSTALADO]%b' "$TC_YELLOW" "$TC_NC"
    fi
}

tc_checkuser_write_server() {
    mkdir -p "$TC_CHECK_DIR"
    cat > "$TC_CHECK_PY" <<'EOF'
#!/usr/bin/env python3
# encoding: utf-8
import http.server
import socketserver
import json
import sys
import os
import subprocess
from datetime import datetime

PORT = 5000
if len(sys.argv) > 1:
    try:
        PORT = int(sys.argv[1])
    except ValueError:
        pass

DB_PATH = "/etc/tunnelcore/users.db"


class CheckUserHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # Endpoint: /checkUser?user=USERNAME o /checkUser/USERNAME
        path = self.path.split("?")[0].strip("/")
        user = ""

        if "?" in self.path:
            query = self.path.split("?")[1]
            params = dict(qc.split("=") for qc in query.split("&") if "=" in qc)
            user = params.get("user", "")

        if not user and "/" in path:
            user = path.split("/")[1]
        elif not user and path and path != "checkUser":
            user = path

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

        with open(DB_PATH, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                parts = [p.strip() for p in line.split("|")]
                if len(parts) >= 3 and parts[0] == user:
                    expiry_str = parts[2]
                    limit_str = parts[3] if len(parts) >= 4 else "1"

                    # Conexiones activas
                    try:
                        p = subprocess.run(
                            ["ps", "-u", user],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            text=True,
                        )
                        act_conns = sum(1 for ln in p.stdout.splitlines() if "sshd" in ln or "dropbear" in ln)
                    except Exception:
                        act_conns = 0

                    days_left = 0
                    is_expired = False
                    try:
                        exp_dt = datetime.strptime(expiry_str, "%Y-%m-%d")
                        diff = (exp_dt - today).days + 1
                        days_left = max(0, diff)
                        is_expired = diff <= 0
                    except Exception:
                        pass

                    return {
                        "username": user,
                        "count_connection": act_conns,
                        "limit_connection": int(limit_str) if limit_str.isdigit() else 1,
                        "expiration_date": expiry_str,
                        "expiration_days": days_left,
                        "is_active": not is_expired,
                    }
        return None

    def _respond(self, code, data):
        body = json.dumps(data).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


def main():
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("0.0.0.0", PORT), CheckUserHandler) as httpd:
        httpd.serve_forever()


if __name__ == "__main__":
    main()
EOF
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

tc_checkuser_menu() {
    while true; do
        tc_clear
        local cur_port="5000"
        [[ -f "$TC_CHECK_CONF" ]] && cur_port="$(grep -oE '[0-9]+' "$TC_CHECK_CONF" || echo "5000")"

        tc_title "GESTIÓN CHECKUSERS (API ANDROID) $(tc_checkuser_status_mark)"

        if ! tc_checkuser_is_running; then
            tc_opt "1" "ACTIVAR CHECKUSER (Puerto 5000)"
            tc_opt "2" "ACTIVAR EN PUERTO PERSONALIZADO"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01)
                    tc_checkuser_start "5000"
                    if tc_checkuser_is_running; then
                        tc_msg_ok "CheckUser API activa en puerto 5000."
                    else
                        tc_msg_err "Error al iniciar CheckUser."
                    fi
                    tc_pause
                    ;;
                2|02)
                    printf '%bPuerto de escucha CheckUser [1-65535]:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r port
                    if tc_valid_port "$port"; then
                        tc_checkuser_start "$port"
                        tc_msg_ok "CheckUser activo en puerto $port."
                    else
                        tc_msg_err "Puerto no válido."
                    fi
                    tc_pause
                    ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        else
            local ip
            ip="$(tc_public_ip)"
            printf '%bPUERTO:%b %b%s%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_GREEN" "$cur_port" "$TC_NC"
            printf '%bURL API:%b %bhttp://%s:%s/checkUser?user=USUARIO%b\n' "$TC_DARK_GREEN" "$TC_NC" "$TC_WHITE" "$ip" "$cur_port" "$TC_NC"
            tc_line
            tc_opt "1" "DESACTIVAR CHECKUSER"
            tc_opt "2" "CAMBIAR PUERTO"
            tc_opt "3" "REINICIAR SERVICIO"
            tc_line
            tc_opt "0" "VOLVER"
            tc_line
            tc_prompt
            read -r opt
            case "$opt" in
                1|01)
                    tc_checkuser_stop
                    tc_msg_ok "CheckUser detenido."
                    tc_pause
                    ;;
                2|02)
                    printf '%bNuevo puerto:%b ' "$TC_DARK_GREEN" "$TC_NC"
                    read -r new_p
                    if tc_valid_port "$new_p"; then
                        tc_checkuser_start "$new_p"
                        tc_msg_ok "Puerto actualizado a $new_p."
                    else
                        tc_msg_err "Puerto no válido."
                    fi
                    tc_pause
                    ;;
                3|03)
                    systemctl restart tunnelcore-checkuser >/dev/null 2>&1
                    tc_msg_ok "CheckUser reiniciado."
                    tc_pause
                    ;;
                0|00) break ;;
                *) tc_msg_err "Opción no válida."; sleep 1 ;;
            esac
        fi
    done
}

