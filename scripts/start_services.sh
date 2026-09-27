#!/usr/bin/env bash
# Inicia todos los demonios de observabilidad, tracking y telemetria en los contenedores
set -euo pipefail

echo "Iniciando servicios en la topologia..."

# 0. Verificacion de IPs y Rutas Base
docker exec nms ip addr add 192.168.10.10/24 dev eth1 2>/dev/null || true
docker exec nms ip route replace 192.168.0.0/16 via 192.168.10.1 dev eth1 2>/dev/null || true
docker exec nms ip route replace 10.0.0.0/8 via 192.168.10.1 dev eth1 2>/dev/null || true

docker exec pc1 ip addr add 192.168.20.50/24 dev eth1 2>/dev/null || true
docker exec pc1 ip route replace default via 192.168.20.1 2>/dev/null || true

for r in r-gestion r1 r2 r-acceso; do
    if ! docker exec "$r" pgrep -f "snmpd" >/dev/null 2>&1; then
        docker exec "$r" snmpd -u root -C -c /etc/snmp/snmpd.conf 2>/dev/null || true
        echo "  ✓ snmpd iniciado en $r"
    else
        echo "  ✓ snmpd ya activo en $r"
    fi
done

# 1. Routers - Agentes Opcionales de Auto-Remediacion
for node in r1 r2 r-acceso; do
    if docker exec "$node" test -f /usr/local/bin/remediation_server.py 2>/dev/null; then
        if ! docker exec "$node" pgrep -f "remediation_server.py" >/dev/null 2>&1; then
            docker exec -d "$node" python3 /usr/local/bin/remediation_server.py
            echo "  ✓ Remediation Server iniciado en $node"
        else
            echo "  ✓ Remediation Server ya activo en $node"
        fi
    fi
done

# 2. R-ACCESO - SLA Tracker (Deteccion y Conmutacion Autonoma L3)
if ! docker exec r-acceso pgrep -f "sla_tracker.sh" >/dev/null 2>&1; then
    docker exec -d r-acceso bash /usr/local/bin/sla_tracker.sh
    echo "  ✓ SLA Tracker iniciado en r-acceso"
else
    echo "  ✓ SLA Tracker ya activo en r-acceso"
fi

# 3. NMS - Monitor Definitivo de Telemetria y Bitacora Forense
if ! docker exec nms pgrep -f "monitor_definitivo.py" >/dev/null 2>&1; then
    docker exec -d nms python3 /app/monitor_definitivo.py
    echo "  ✓ Monitor Definitivo NMS iniciado"
else
    echo "  ✓ Monitor Definitivo NMS ya activo"
fi

echo "Todos los servicios estan operativos."
