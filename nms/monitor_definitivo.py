#!/usr/bin/env python3
import time
import subprocess
import datetime
import os
import sys

COMMUNITY = "redes2026"
CLIENT_IP = "192.168.20.50"
ROUTERS = {
    "R1": "192.168.11.2",
    "R2": "192.168.12.2"
}
R_ACCESO_IPS = ["192.168.21.2", "192.168.22.2"]
LOG_FILE = "/app/incidentes_red.log"

def log_event(level, message):
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    formatted = f"[{now}] [{level}] {message}"
    print(formatted, flush=True)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(formatted + "\n")

def ping_host(ip, timeout=1):
    try:
        res = subprocess.run(
            ["ping", "-c", "1", "-W", str(timeout), ip],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        return res.returncode == 0
    except Exception:
        return False

def snmp_get(ip, oid, timeout=1):
    try:
        cmd = ["snmpget", "-v", "2c", "-c", COMMUNITY, "-t", str(timeout), "-Oqv", ip, oid]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 1)
        if res.returncode == 0:
            return res.stdout.strip().strip('"')
    except Exception:
        pass
    return None

def snmp_walk(ip, oid, timeout=1):
    results = {}
    try:
        cmd = ["snmpwalk", "-v", "2c", "-c", COMMUNITY, "-t", str(timeout), "-Oq", ip, oid]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 2)
        if res.returncode == 0:
            for line in res.stdout.strip().splitlines():
                parts = line.split(maxsplit=1)
                if len(parts) == 2:
                    results[parts[0]] = parts[1].strip('"')
    except Exception:
        pass
    return results

def get_interfaces(ip):
    # Returns {if_name: status_int} (1=UP, 2=DOWN)
    names = {}
    statuses = {}
    raw_descr = snmp_walk(ip, "1.3.6.1.2.1.2.2.1.2")
    raw_status = snmp_walk(ip, "1.3.6.1.2.1.2.2.1.8")
    
    for k, v in raw_descr.items():
        idx = k.split(".")[-1]
        names[idx] = v
        
    for k, v in raw_status.items():
        idx = k.split(".")[-1]
        try:
            statuses[idx] = int(v)
        except ValueError:
            pass
            
    res = {}
    for idx, name in names.items():
        if idx in statuses and name not in ["lo", "eth0"]:
            res[name] = statuses[idx]
    return res

def get_r_acceso_nexthop():
    # Multi-hop query: try 192.168.21.2 first, then 192.168.22.2
    for ip in R_ACCESO_IPS:
        hop = snmp_get(ip, "1.3.6.1.2.1.4.21.1.7.0.0.0.0", timeout=1)
        if hop and hop != "0.0.0.0":
            return hop, ip
    return None, None

def main():
    print("Iniciando Monitor de Red y Telemetria NMS...", flush=True)
    hop, active_ip = get_r_acceso_nexthop()
    initial_gw = hop if hop else "192.168.21.1"
    
    log_event("INFO", f"Topologia en linea. Gateway activo en R-ACCESO: {initial_gw}")
    
    last_client_up = ping_host(CLIENT_IP)
    last_gateway = initial_gw
    last_ifaces = {} # (router_name, if_name) -> status (1=UP, 2=DOWN)
    
    while True:
        try:
            # 1. Auditoria de PC1 Cliente
            client_up = ping_host(CLIENT_IP)
            if client_up != last_client_up:
                if not client_up:
                    log_event("CRITICO", f"PC1 Cliente ({CLIENT_IP}) sin respuesta ICMP (Host inaccesible).")
                else:
                    log_event("RECUPERADO", f"PC1 Cliente ({CLIENT_IP}) restablecio conectividad ICMP.")
                last_client_up = client_up

            # 2. Auditoria de Gateway R-ACCESO (Failover)
            curr_gw, target_ip = get_r_acceso_nexthop()
            if curr_gw and curr_gw != last_gateway:
                if "22.1" in curr_gw or "10.0.0.2" in curr_gw:
                    log_event("FAILOVER", f"¡FALLA EN CAMINO PRIMARIO! Trafico REDIRIGIDO hacia R2 ({curr_gw}) via IP SLA / Ruta Flotante.")
                elif "21.1" in curr_gw:
                    log_event("RECUPERADO", f"¡CAMINO PRIMARIO RESTABLECIDO! Trafico NORMALIZADO de vuelta a R1 ({curr_gw}).")
                last_gateway = curr_gw

            # 3. Auditoria de Interfaces Fisicas
            nodes_to_check = dict(ROUTERS)
            nodes_to_check["R-ACCESO"] = target_ip if target_ip else R_ACCESO_IPS[0]
            
            for r_name, r_ip in nodes_to_check.items():
                ifaces = get_interfaces(r_ip)
                for if_name, st in ifaces.items():
                    key = (r_name, if_name)
                    if key in last_ifaces and last_ifaces[key] != st:
                        if st == 2:
                            log_event("CRITICO", f"{r_name} -> {if_name} cayo a DOWN!")
                        elif st == 1:
                            log_event("RECUPERADO", f"{r_name} -> {if_name} se restauro a UP.")
                    last_ifaces[key] = st

        except Exception as e:
            pass

        time.sleep(2)

if __name__ == "__main__":
    main()
