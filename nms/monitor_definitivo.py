#!/usr/bin/env python3
"""
Motor de Telemetria NMS con Auto-Remediacion (Self-Healing) y Calculo de MTTR
Laboratorio de Enrutamiento L3 con Alta Disponibilidad
Fase 5: Observabilidad Avanzada de Failover, Self-Healing y MTTR
"""
import time
import subprocess
import datetime
import os
import sys
import json
import re
import requests
from prometheus_client import start_http_server, Gauge, Counter, Histogram

with open("/run/secrets/snmp_community", "r", encoding="utf-8") as secret_file:
    COMMUNITY = secret_file.read().strip()
if not COMMUNITY:
    raise RuntimeError("Falta la comunidad SNMP en /run/secrets/snmp_community")
CLIENT_IP = "192.168.20.50"
REMEDIATION_PORT = 5000
PROMETHEUS_PORT = 8000

ROUTERS = {
    "R1": "192.168.11.2",
    "R2": "192.168.12.2"
}
R_ACCESO_MGMT = "r-acceso"
# NET-SNMP-EXTEND-MIB::nsExtendOutput1Line."activeRoute"
ACTIVE_ROUTE_OID = "1.3.6.1.4.1.8072.1.3.2.3.1.1.11.97.99.116.105.118.101.82.111.117.116.101"
LOG_FILE = "/app/incidentes_red.log"

# ==============================================================================
# METRICAS PROMETHEUS (FASE 5: OBSERVABILIDAD AVANZADA HA & SELF-HEALING)
# ==============================================================================

# 1. Estados de Conectividad y Ruta
PROM_PC1_REACHABLE = Gauge(
    "network_pc1_reachable",
    "Estado de conectividad ICMP hacia el host cliente PC1 (1=UP/Alcanzable, 0=DOWN/Inaccesible)"
)
PROM_PRIMARY_PATH_ACTIVE = Gauge(
    "network_primary_path_active",
    "Estado del camino primario L3 en R-ACCESO hacia R1 (1=Primario Activo/R1, 0=Secundario/R2)"
)
PROM_BACKUP_PATH_ACTIVE = Gauge(
    "network_backup_path_active",
    "Estado del camino de contingencia L3 en R-ACCESO hacia R2 (1=Secundario Activo/R2, 0=Inactivo)"
)
PROM_FAILOVER_STATE = Gauge(
    "network_failover_state",
    "Estado discreto de conmutacion L3 (0=Nominal/Primario R1, 1=Failover Activo/R2)",
    ["router"]
)
PROM_INTERFACE_DOWN_STATE = Gauge(
    "network_interface_down_state",
    "Estado de caida de interfaces monitoreadas (1=DOWN, 0=UP)",
    ["router", "interface"]
)

# 2. Conmutacion de Ruta (Failover)
PROM_FAILOVERS_TOTAL = Counter(
    "network_failovers_total",
    "Total acumulado de eventos de failover L3 conmutados",
    ["router", "path", "reason"]
)

# 3. Auto-remediacion (Self-Healing NetDevOps)
PROM_AUTOHEAL_TOTAL = Counter(
    "network_autoheal_total",
    "Total acumulado de acciones de auto-remediacion solicitadas",
    ["router", "interface"]
)
PROM_AUTOHEAL_SUCCESS_TOTAL = Counter(
    "network_autoheal_success_total",
    "Total de acciones de auto-remediacion ejecutadas exitosamente por el agente NetDevOps",
    ["router", "interface"]
)
PROM_AUTOHEAL_FAILURE_TOTAL = Counter(
    "network_autoheal_failure_total",
    "Total de acciones de auto-remediacion fallidas",
    ["router", "interface"]
)
PROM_AUTOHEAL_ACTIVE = Gauge(
    "network_autoheal_active",
    "Indica si hay un proceso de auto-remediacion en curso para una interfaz (1=En curso, 0=Inactivo)",
    ["router", "interface"]
)
PROM_AUTOHEAL_DURATION_SECONDS = Histogram(
    "network_autoheal_duration_seconds",
    "Latencia del protocolo de remediacion HTTP hacia el router (segundos)",
    ["router", "interface"],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0]
)

# 4. Incidentes y Recuperaciones
PROM_INCIDENTS_TOTAL = Counter(
    "network_incidents_total",
    "Total acumulado de incidentes de red detectados",
    ["router", "event"]
)
PROM_CRITICAL_INCIDENTS_TOTAL = Counter(
    "network_critical_incidents_total",
    "Total acumulado de incidentes criticos (caida de enlaces o hosts)",
    ["router", "event"]
)
PROM_RECOVERIES_TOTAL = Counter(
    "network_recoveries_total",
    "Total acumulado de recuperaciones confirmadas de conectividad o enlaces",
    ["router", "event"]
)

# 5. MTTR (Mean Time to Recovery)
PROM_MTTR_SECONDS = Histogram(
    "network_mttr_seconds",
    "Distribucion y acumulado del tiempo medio de recuperacion ante fallas (segundos)",
    ["target"],
    buckets=[0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 7.5, 10.0, 15.0, 30.0, 60.0]
)
PROM_LAST_MTTR_SECONDS = Gauge(
    "network_last_mttr_seconds",
    "Ultimo tiempo de recuperacion medido ante falla (segundos)",
    ["target"]
)
PROM_MTTR_CURRENT_SECONDS = Gauge(
    "network_mttr_current_seconds",
    "MTTR promedio historico acumulado del sistema (segundos)"
)

# Lista en memoria de todas las muestras de MTTR
ALL_MTTR_SAMPLES = []

def init_prometheus_metrics(initial_gw, client_online):
    """Inicializa contadores y estados para evitar series ausentes en Prometheus"""
    is_primary = bool(initial_gw and "21.1" in initial_gw)
    PROM_PC1_REACHABLE.set(1 if client_online else 0)
    PROM_PRIMARY_PATH_ACTIVE.set(1 if is_primary else 0)
    is_backup = initial_gw == "192.168.22.1"
    PROM_BACKUP_PATH_ACTIVE.set(1 if is_backup else 0)
    PROM_FAILOVER_STATE.labels(router="r-acceso").set(0 if is_primary else (1 if is_backup else -1))
    
    # Pre-inicializar interfaces clave
    monitored_interfaces = [
        ("R1", "eth3"),
        ("R2", "eth3"),
        ("R-ACCESO", "eth1"),
        ("R-ACCESO", "eth2")
    ]
    for r, iface in monitored_interfaces:
        PROM_INTERFACE_DOWN_STATE.labels(router=r, interface=iface).set(0)
        PROM_AUTOHEAL_ACTIVE.labels(router=r, interface=iface).set(0)
        PROM_AUTOHEAL_TOTAL.labels(router=r, interface=iface)
        PROM_AUTOHEAL_SUCCESS_TOTAL.labels(router=r, interface=iface)
        PROM_AUTOHEAL_FAILURE_TOTAL.labels(router=r, interface=iface)

    PROM_FAILOVERS_TOTAL.labels(router="r-acceso", path="secondary", reason="primary_link_failure")
    for r in ["R1", "R2", "R-ACCESO"]:
        PROM_INCIDENTS_TOTAL.labels(router=r, event="interface_down")
        PROM_CRITICAL_INCIDENTS_TOTAL.labels(router=r, event="interface_down")
        PROM_RECOVERIES_TOTAL.labels(router=r, event="interface_up")
    PROM_INCIDENTS_TOTAL.labels(router="pc1", event="icmp_failure")
    PROM_CRITICAL_INCIDENTS_TOTAL.labels(router="pc1", event="icmp_failure")
    PROM_RECOVERIES_TOTAL.labels(router="pc1", event="icmp_recovery")
    PROM_RECOVERIES_TOTAL.labels(router="R-ACCESO", event="path_restored")

    # Cargar muestras historicas de MTTR desde la bitacora forense para MTTR inicial
    if os.path.exists(LOG_FILE):
        try:
            with open(LOG_FILE, "r", encoding="utf-8") as f:
                for line in f:
                    m = re.search(r"MTTR:\s*([0-9\.]+)s", line)
                    if m:
                        ALL_MTTR_SAMPLES.append(float(m.group(1)))
            if ALL_MTTR_SAMPLES:
                avg = round(sum(ALL_MTTR_SAMPLES) / len(ALL_MTTR_SAMPLES), 2)
                PROM_MTTR_CURRENT_SECONDS.set(avg)
                PROM_LAST_MTTR_SECONDS.labels(target="system").set(ALL_MTTR_SAMPLES[-1])
        except Exception:
            pass

# ==============================================================================
# LOGICA DE SONDEO Y TELEMETRIA NMS
# ==============================================================================

def log_event(level, message):
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    formatted = f"[{now}] [{level}] {message}"
    print(formatted, flush=True)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(f"{formatted}\n")

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
    """Lee la ruta efectiva del kernel por SNMP y el plano de gestion."""
    route = snmp_get(R_ACCESO_MGMT, ACTIVE_ROUTE_OID, timeout=1)
    if route:
        match = re.fullmatch(r"default via (192\.168\.(?:21|22)\.1) dev eth[12](?:\s+.*)?", route)
        if match:
            return match.group(1)
    return None

def trigger_self_healing(router_name, router_ip, if_name):
    """Envia orden de auto-remediacion al agente NetDevOps del router con medicion de duracion"""
    t_start = time.time()
    try:
        url = f"http://{router_ip}:{REMEDIATION_PORT}/remediate"
        payload = {"action": "restart_interface", "interface": if_name}
        resp = requests.post(url, json=payload, timeout=2)
        exec_dur = round(time.time() - t_start, 4)
        if resp.status_code == 200:
            PROM_AUTOHEAL_DURATION_SECONDS.labels(router=router_name, interface=if_name).observe(exec_dur)
            ms_info = f" (latencia: {round(exec_dur*1000, 1)}ms)"
            log_event("AUTO-HEAL", f"Protocolo NetDevOps: Orden de reactivacion ejecutada con exito en {router_name} para {if_name}{ms_info}.")
            return True
    except Exception as e:
        log_event("ERROR", f"Fallo al conectar con agente de remediacion en {router_name} ({e})")
    return False

def record_mttr_sample(target_label, elapsed):
    """Registra una muestra de MTTR en todas las metricas correspondientes"""
    ALL_MTTR_SAMPLES.append(elapsed)
    avg_mttr = round(sum(ALL_MTTR_SAMPLES) / len(ALL_MTTR_SAMPLES), 2)
    PROM_MTTR_CURRENT_SECONDS.set(avg_mttr)
    PROM_MTTR_SECONDS.labels(target=target_label).observe(elapsed)
    PROM_LAST_MTTR_SECONDS.labels(target=target_label).set(elapsed)

def main():
    print("Iniciando Motor de Telemetria NMS Fase 5 (HA, Self-Healing y MTTR)...", flush=True)
    
    # Iniciar Servidor de Metricas Prometheus
    try:
        start_http_server(PROMETHEUS_PORT)
        log_event("INFO", f"Servidor de metricas Prometheus activo en http://0.0.0.0:{PROMETHEUS_PORT}/metrics")
    except Exception as e:
        log_event("ERROR", f"Error al iniciar servidor de metricas Prometheus: {e}")

    initial_gw = get_r_acceso_nexthop()
    initial_client_up = ping_host(CLIENT_IP)
    
    init_prometheus_metrics(initial_gw, initial_client_up)
    log_event("INFO", f"Topologia en linea. Gateway activo en R-ACCESO: {initial_gw or 'desconocido'}")
    
    last_client_up = initial_client_up
    client_fail_time = None
    last_gateway = initial_gw
    last_ifaces = {}      # (router_name, if_name) -> status (1=UP, 2=DOWN)
    iface_fail_times = {} # (router_name, if_name) -> timestamp de caida
    
    while True:
        try:
            # 1. Auditoria de PC1 Cliente (ICMP)
            client_up = ping_host(CLIENT_IP)
            PROM_PC1_REACHABLE.set(1 if client_up else 0)
            
            if client_up != last_client_up:
                if not client_up:
                    client_fail_time = time.time()
                    PROM_INCIDENTS_TOTAL.labels(router="pc1", event="icmp_failure").inc()
                    PROM_CRITICAL_INCIDENTS_TOTAL.labels(router="pc1", event="icmp_failure").inc()
                    log_event("CRITICO", f"PC1 Cliente ({CLIENT_IP}) sin respuesta ICMP (Host inaccesible).")
                else:
                    dur_str = ""
                    PROM_RECOVERIES_TOTAL.labels(router="pc1", event="icmp_recovery").inc()
                    if client_fail_time:
                        elapsed = round(time.time() - client_fail_time, 2)
                        record_mttr_sample("pc1", elapsed)
                        dur_str = f" (Interrupcion resuelta en {elapsed}s | MTTR: {elapsed}s)"
                        client_fail_time = None
                    log_event("RECUPERADO", f"PC1 Cliente ({CLIENT_IP}) restablecio conectividad ICMP.{dur_str}")
                last_client_up = client_up

            # 2. Ruta real consultada antes de las auditorias SNMP mas lentas.
            curr_gw = get_r_acceso_nexthop()
            PROM_PRIMARY_PATH_ACTIVE.set(1 if curr_gw == "192.168.21.1" else 0)
            PROM_BACKUP_PATH_ACTIVE.set(1 if curr_gw == "192.168.22.1" else 0)
            PROM_FAILOVER_STATE.labels(router="r-acceso").set(
                0 if curr_gw == "192.168.21.1" else (1 if curr_gw == "192.168.22.1" else -1)
            )
            if curr_gw and curr_gw != last_gateway:
                if last_gateway is not None and curr_gw == "192.168.22.1":
                    PROM_FAILOVERS_TOTAL.labels(router="r-acceso", path="secondary", reason="primary_link_failure").inc()
                    PROM_INCIDENTS_TOTAL.labels(router="R-ACCESO", event="failover_r2").inc()
                    log_event("FAILOVER", f"¡FALLA EN CAMINO PRIMARIO! Trafico REDIRIGIDO hacia R2 ({curr_gw}) via IP SLA / Ruta Flotante.")
                elif last_gateway is not None and curr_gw == "192.168.21.1":
                    PROM_RECOVERIES_TOTAL.labels(router="R-ACCESO", event="path_restored").inc()
                    log_event("RECUPERADO", f"¡CAMINO PRIMARIO RESTABLECIDO! Trafico NORMALIZADO de vuelta a R1 ({curr_gw}).")
                last_gateway = curr_gw

            # 3. Auditoria de Interfaces Fisicas y Auto-Remediacion (Self-Healing)
            nodes_to_check = dict(ROUTERS)
            nodes_to_check["R-ACCESO"] = R_ACCESO_MGMT
            
            for r_name, r_ip in nodes_to_check.items():
                ifaces = get_interfaces(r_ip)
                for if_name, st in ifaces.items():
                    key = (r_name, if_name)

                    if key in last_ifaces and last_ifaces[key] != st:
                        if st == 2:
                            # FASE 1: DOWN detectado
                            iface_fail_times[key] = time.time()
                            PROM_INTERFACE_DOWN_STATE.labels(router=r_name, interface=if_name).set(1)
                            PROM_AUTOHEAL_ACTIVE.labels(router=r_name, interface=if_name).set(1)
                            PROM_INCIDENTS_TOTAL.labels(router=r_name, event="interface_down").inc()
                            PROM_CRITICAL_INCIDENTS_TOTAL.labels(router=r_name, event="interface_down").inc()
                            log_event("CRITICO", f"{r_name} -> {if_name} cayo a DOWN!")
                            
                            # FASE 2: Remediacion solicitada
                            log_event("AUTO-HEAL", f"Detectada falla en {r_name} ({if_name}). Evaluando diagnostico y auto-reparacion...")
                            time.sleep(1)
                            PROM_AUTOHEAL_TOTAL.labels(router=r_name, interface=if_name).inc()
                            
                            # FASE 3: Remediacion ejecutada
                            success = trigger_self_healing(r_name, r_ip, if_name)
                            if success:
                                PROM_AUTOHEAL_SUCCESS_TOTAL.labels(router=r_name, interface=if_name).inc()
                            else:
                                PROM_AUTOHEAL_FAILURE_TOTAL.labels(router=r_name, interface=if_name).inc()

                        elif st == 1:
                            # FASE 4: Interfaz recuperada
                            PROM_INTERFACE_DOWN_STATE.labels(router=r_name, interface=if_name).set(0)
                            PROM_AUTOHEAL_ACTIVE.labels(router=r_name, interface=if_name).set(0)
                            PROM_RECOVERIES_TOTAL.labels(router=r_name, event="interface_up").inc()
                            dur_str = ""
                            if key in iface_fail_times:
                                elapsed = round(time.time() - iface_fail_times.pop(key), 2)
                                target_lbl = f"{r_name}:{if_name}"
                                record_mttr_sample(target_lbl, elapsed)
                                dur_str = f" (Falla resuelta en {elapsed}s | MTTR: {elapsed}s)"
                            log_event("RECUPERADO", f"{r_name} -> {if_name} se restauro a UP.{dur_str}")
                    last_ifaces[key] = st

        except Exception as e:
            pass

        time.sleep(2)

if __name__ == "__main__":
    main()
