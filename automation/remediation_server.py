#!/usr/bin/env python3
"""
Laboratorio de Enrutamiento con Alta Disponibilidad y Resiliencia
Extension Fase 5: Telemetria de duracion de ejecucion en respuestas HTTP
"""
import os
import sys
import json
import time
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 5000

class RemediationHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path == "/health":
            hostname = os.uname().nodename
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "online", "router": hostname}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/remediate":
            t_start = time.time()
            try:
                length = int(self.headers.get("Content-Length", 0))
                body = json.loads(self.rfile.read(length).decode())
                action = body.get("action")
                iface = body.get("interface")

                if iface not in ["eth1", "eth2", "eth3"]:
                    self.send_response(400)
                    self.end_headers()
                    self.wfile.write(b'{"error": "Interfaz no permitida"}')
                    return

                if action == "restart_interface":
                    subprocess.run(["ip", "link", "set", iface, "up"], check=True)
                    exec_ms = round((time.time() - t_start) * 1000, 2)
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    resp = {
                        "status": "success",
                        "interface": iface,
                        "state": "UP",
                        "action": "restart_interface",
                        "execution_ms": exec_ms
                    }
                    self.wfile.write(json.dumps(resp).encode())
                    return

                elif action == "flush_arp":
                    subprocess.run(["ip", "neigh", "flush", "dev", iface], check=True)
                    exec_ms = round((time.time() - t_start) * 1000, 2)
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    resp = {
                        "status": "success",
                        "interface": iface,
                        "action": "flush_arp",
                        "execution_ms": exec_ms
                    }
                    self.wfile.write(json.dumps(resp).encode())
                    return

            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode())
                return

        self.send_response(404)
        self.end_headers()

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), RemediationHandler)
    server.serve_forever()
