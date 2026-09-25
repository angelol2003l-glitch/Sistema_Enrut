#!/usr/bin/env bash
# Inicia todos los demonios de observabilidad, tracking y telemetria en los contenedores
set -euo pipefail

echo "Iniciando servicios en la topologia..."

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
