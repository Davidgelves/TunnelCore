#!/usr/bin/env python3
# encoding: utf-8
# ═══════════════════════════════════════════════════════════════
#  TunnelCore — Proxy HTTP / SOCKS (Payload / WebSocket / Auto)
#  Optimizado: socket.listen(128), thread cleanup, modo AUTO/NEUTRO
#  Autor: J DAVID AG
# ═══════════════════════════════════════════════════════════════
import socket
import threading
import select
import sys
import time
from datetime import datetime

IP = "0.0.0.0"
PORT = 80
HTTP_STATUS = "AUTO"
DEFAULT_HOST = "127.0.0.1:22"
CUSTOM_BANNER = ""
PASS = ""

if len(sys.argv) > 1:
    try:
        PORT = int(sys.argv[1])
    except ValueError:
        pass

if len(sys.argv) > 2:
    HTTP_STATUS = str(sys.argv[2]).strip().upper()

if len(sys.argv) > 3:
    DEFAULT_HOST = str(sys.argv[3]).strip()

if len(sys.argv) > 4:
    CUSTOM_BANNER = str(sys.argv[4])

BUFLEN = 65536
TIMEOUT = 60


def get_response_bytes(status, banner, text_request=""):
    st = str(status).strip().upper()

    # Modo AUTO / NEUTRO: Detecta automáticamente WebSocket o Payload 200
    if st == "AUTO" or st == "NEUTRO" or st == "AUTO/NEUTRO":
        low = text_request.lower()
        if "websocket" in low or "upgrade" in low or "sec-websocket" in low:
            return (
                b"HTTP/1.1 101 Switching Protocols\r\n"
                b"Upgrade: websocket\r\n"
                b"Connection: Upgrade\r\n"
                b"\r\n"
            )
        elif banner:
            body = banner.encode("latin1", errors="replace")
            return (
                b"HTTP/1.1 200 OK\r\n"
                b"Content-Type: text/html; charset=utf-8\r\n"
                + f"Content-Length: {len(body)}\r\n".encode("latin1")
                + b"Connection: keep-alive\r\n\r\n"
                + body
            )
        else:
            return (
                b"HTTP/1.1 200 OK\r\n"
                b"Connection: keep-alive\r\n"
                b"Content-Length: 0\r\n"
                b"\r\n"
                b"HTTP/1.1 200 Connection Established\r\n"
                b"\r\n"
            )

    # Modo Fijo
    if st == "101":
        return (
            b"HTTP/1.1 101 Switching Protocols\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n"
            b"\r\n"
        )
    elif st == "200" and not banner:
        return (
            b"HTTP/1.1 200 OK\r\n"
            b"Connection: keep-alive\r\n"
            b"Content-Length: 0\r\n"
            b"\r\n"
            b"HTTP/1.1 200 Connection Established\r\n"
            b"\r\n"
        )
    elif banner:
        body = banner.encode("latin1", errors="replace")
        return (
            f"HTTP/1.1 {st} OK\r\n".encode("latin1")
            + b"Content-Type: text/html; charset=utf-8\r\n"
            + f"Content-Length: {len(body)}\r\n".encode("latin1")
            + b"Connection: keep-alive\r\n\r\n"
            + body
        )
    else:
        return f"HTTP/1.1 {st} OK\r\nConnection: keep-alive\r\nContent-Length: 0\r\n\r\n".encode("latin1")


class Server:
    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.running = False
        self.soc = None
        self.threads = []
        self.lock = threading.Lock()

    def start(self):
        self.soc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.settimeout(2)
        self.soc.bind((self.host, self.port))
        self.soc.listen(128)
        self.running = True

        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] TunnelCore Proxy en {self.host}:{self.port} (Status {HTTP_STATUS})")

        try:
            while self.running:
                try:
                    c, addr = self.soc.accept()
                    c.setblocking(True)
                except socket.timeout:
                    self._cleanup_dead_threads()
                    continue
                except OSError:
                    break

                conn = ConnectionHandler(c, self, addr)
                conn.daemon = True
                conn.start()

                with self.lock:
                    self.threads.append(conn)

        finally:
            self.stop()

    def _cleanup_dead_threads(self):
        with self.lock:
            self.threads = [t for t in self.threads if t.is_alive()]

    def stop(self):
        self.running = False
        if self.soc:
            try:
                self.soc.close()
            except Exception:
                pass


class ConnectionHandler(threading.Thread):
    def __init__(self, client_sock, server, addr):
        super().__init__()
        self.client = client_sock
        self.server = server
        self.addr = addr
        self.target = None
        self.closed = False

    def close(self):
        if self.closed:
            return
        self.closed = True
        for s in (self.client, self.target):
            if s:
                try:
                    s.shutdown(socket.SHUT_RDWR)
                except Exception:
                    pass
                try:
                    s.close()
                except Exception:
                    pass

    def run(self):
        try:
            buf = self.client.recv(BUFLEN)
            if not buf:
                return

            text = buf.decode("latin1", errors="replace")
            host_port = self._find_header(text, "X-Real-Host")
            if not host_port:
                host_port = DEFAULT_HOST

            split = self._find_header(text, "X-Split")
            if split:
                try:
                    self.client.recv(BUFLEN)
                except Exception:
                    pass

            allowed = (
                host_port.startswith("127.0.0.1")
                or host_port.startswith("localhost")
                or host_port.startswith("0.0.0.0")
            )

            if not allowed:
                self.client.sendall(b"HTTP/1.1 403 Forbidden\r\n\r\n")
                return

            # Respuesta según modo (AUTO detecta websocket vs payload)
            response_bytes = get_response_bytes(HTTP_STATUS, CUSTOM_BANNER, text)

            self._connect_target(host_port)
            self.client.sendall(response_bytes)
            self._bridge()

        except Exception:
            pass
        finally:
            self.close()

    def _find_header(self, text, header):
        idx = text.lower().find(header.lower() + ":")
        if idx == -1:
            return ""
        colon = text.find(":", idx)
        line_end = text.find("\r\n", colon)
        if line_end == -1:
            return ""
        return text[colon + 1 : line_end].strip()

    def _connect_target(self, host_port):
        if ":" in host_port:
            host, port_str = host_port.split(":", 1)
            port = int(port_str)
        else:
            host, port = "127.0.0.1", 22

        info = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)[0]
        self.target = socket.socket(info[0], info[1], info[2])
        self.target.settimeout(10)
        self.target.connect(info[4])
        self.target.settimeout(None)

    def _bridge(self):
        socs = [self.client, self.target]
        idle_count = 0

        while idle_count < TIMEOUT:
            r, _, err = select.select(socs, [], socs, 1.0)
            if err:
                break
            if r:
                idle_count = 0
                for s in r:
                    try:
                        data = s.recv(BUFLEN)
                        if not data:
                            return
                        other = self.target if s is self.client else self.client
                        other.sendall(data)
                    except Exception:
                        return
            else:
                idle_count += 1


def main():
    server = Server(IP, PORT)
    try:
        server.start()
    except KeyboardInterrupt:
        server.stop()


if __name__ == "__main__":
    main()
