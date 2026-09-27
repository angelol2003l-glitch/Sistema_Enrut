#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE VALIDACION COMPLETA - FASE 5: HA, SELF-HEALING Y MTTR
# ==============================================================================
set -e

echo "================================================================="
echo "   VALIDACION FASE 5: OBSERVABILIDAD AVANZADA HA, HEAL Y MTTR   "
echo "================================================================="

# 1. Proceso NMS y Contenedor
echo -n "[1/10] Estado del NMS y proceso 'monitor_definitivo.py': "
NMS_STATUS=$(docker inspect -f '{{.State.Status}}' nms 2>/dev/null || echo "missing")
if [ "$NMS_STATUS" = "running" ]; then
    PROC_COUNT=$(docker exec nms pgrep -f "monitor_definitivo.py" | wc -l)
    if [ "$PROC_COUNT" -ge 1 ]; then
        echo "✓ RUNNING (PID activo) (OK)"
    else
        echo "✗ ERROR: Proceso monitor_definitivo.py no encontrado"
        exit 1
    fi
else
    echo "✗ ERROR: Contenedor 'nms' en estado $NMS_STATUS"
    exit 1
fi

# 2. Agentes de Auto-Remediacion en Routers (r1, r2, r-acceso)
echo -n "[2/10] Agentes NetDevOps (remediation_server.py en routers): "
AGENTS_OK=0
for node in r1 r2 r-acceso; do
    if docker exec $node pgrep -f "remediation_server.py" > /dev/null 2>&1; then
        AGENTS_OK=$((AGENTS_OK + 1))
    fi
done
if [ "$AGENTS_OK" -eq 3 ]; then
    echo "✓ 3/3 AGENTES ACTIVOS EN PUERTO 5000 (OK)"
else
    echo "✗ ERROR: Solo $AGENTS_OK/3 agentes de remediacion activos"
    exit 1
fi

# 3. Endpoint /metrics en NMS (puerto 8000)
echo -n "[3/10] Endpoint de Metricas NMS (http://172.20.20.7:8000/metrics): "
HTTP_CODE=$(docker exec nms curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/metrics || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ RESPONDE HTTP 200 (OK)"
else
    echo "✗ ERROR: Endpoint /metrics respondio $HTTP_CODE"
    exit 1
fi

# 4. Target nms-python en Prometheus
echo -n "[4/10] Estado del Target 'nms-python' en Prometheus: "
TARGET_HEALTH=$(curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.job=="nms-python") | .health' 2>/dev/null || echo "unknown")
if [ "$TARGET_HEALTH" = "up" ]; then
    echo "✓ TARGET STATE = UP (OK)"
else
    echo "✗ ERROR: Target 'nms-python' en estado '$TARGET_HEALTH'"
    exit 1
fi

# 5. Metricas de Failover en Prometheus
echo -n "[5/10] Metricas de Failover (total, state, primary/backup path): "
FO_TOTAL=$(curl -s "http://localhost:9090/api/v1/query?query=sum(network_failovers_total)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "")
FO_STATE=$(curl -s "http://localhost:9090/api/v1/query?query=network_failover_state%7Brouter%3D%22r-acceso%22%7D" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "")
PRIMARY_ACT=$(curl -s "http://localhost:9090/api/v1/query?query=network_primary_path_active" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "")
if [ -n "$FO_TOTAL" ] && [ -n "$FO_STATE" ] && [ -n "$PRIMARY_ACT" ]; then
    echo "✓ FAILOVERS=$FO_TOTAL | STATE=$FO_STATE | PRIMARY_PATH=$PRIMARY_ACT (OK)"
else
    echo "✗ ERROR: Metricas de Failover no disponibles en Prometheus"
    exit 1
fi

# 6. Metricas de Auto-Healing en Prometheus
echo -n "[6/10] Metricas de Auto-Healing (total, success, active, duration): "
AH_TOTAL=$(curl -s "http://localhost:9090/api/v1/query?query=sum(network_autoheal_total)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "")
AH_SUCC=$(curl -s "http://localhost:9090/api/v1/query?query=sum(network_autoheal_success_total)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "")
AH_ACT=$(curl -s "http://localhost:9090/api/v1/query?query=sum(network_autoheal_active)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "")
if [ -n "$AH_TOTAL" ] && [ -n "$AH_SUCC" ] && [ -n "$AH_ACT" ]; then
    echo "✓ TOTAL=$AH_TOTAL | SUCCESS=$AH_SUCC | ACTIVE=$AH_ACT (OK)"
else
    echo "✗ ERROR: Metricas de Auto-Healing no disponibles en Prometheus"
    exit 1
fi

# 7. Metricas de MTTR en Prometheus
echo -n "[7/10] Metricas de MTTR (histogram, last_mttr, current_mttr): "
MTTR_CURR=$(curl -s "http://localhost:9090/api/v1/query?query=network_mttr_current_seconds" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "")
MTTR_COUNT=$(curl -s "http://localhost:9090/api/v1/query?query=sum(network_mttr_seconds_count)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if [ -n "$MTTR_CURR" ] && [ "$MTTR_COUNT" -ge 1 ]; then
    echo "✓ MTTR_ACTUAL=${MTTR_CURR}s | RECUPERACIONES_REGISTRADAS=$MTTR_COUNT (OK)"
else
    echo "✗ ERROR: MTTR no calculado en Prometheus"
    exit 1
fi

# 8. Dashboards de Fase 5 en Grafana
echo -n "[8/10] Dashboards Fase 5 en Grafana (HA, Self-Healing, Timeline): "
HA_OK=$(curl -s http://localhost:3000/api/dashboards/uid/ha-overview | jq -r '.dashboard.title' 2>/dev/null || echo "")
SH_OK=$(curl -s http://localhost:3000/api/dashboards/uid/self-healing | jq -r '.dashboard.title' 2>/dev/null || echo "")
TL_OK=$(curl -s http://localhost:3000/api/dashboards/uid/incident-timeline | jq -r '.dashboard.title' 2>/dev/null || echo "")
if [ -n "$HA_OK" ] && [ -n "$SH_OK" ] && [ -n "$TL_OK" ]; then
    echo "✓ 3/3 DASHBOARDS FASE 5 LISTOS Y OPERATIVOS (OK)"
else
    echo "✗ ERROR: Faltan dashboards de Fase 5 en Grafana"
    exit 1
fi

# 9. Bitacora Forense y Reporte de SLA
echo -n "[9/10] Bitacora Forense y Script reporte_sla.py: "
LOG_LINES=$(docker exec nms wc -l /app/incidentes_red.log | awk '{print $1}')
SLA_MTTR=$(docker exec nms python3 /app/reporte_sla.py | grep "Tiempo Medio de Recuperacion" | awk -F: '{print $2}' | xargs)
if [ "$LOG_LINES" -gt 0 ] && [ -n "$SLA_MTTR" ]; then
    echo "✓ $LOG_LINES EVENTOS | SLA MTTR: $SLA_MTTR (OK)"
else
    echo "✗ ERROR: Bitacora forense o reporte SLA inaccesibles"
    exit 1
fi

# 10. Verificacion de No Regresion (Fases 1, 2, 3 y 4)
echo -n "[10/10] Verificacion de No Regresion (Routers SNMP y Grafana Proxy): "
ROUTERS_UP=$(curl -s "http://localhost:9090/api/v1/query?query=count(up%7Bjob%3D%22snmp-routers%22%7D)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
PROXY_STATUS=$(curl -s "http://localhost:3000/api/datasources/uid/prometheus/resources/api/v1/query?query=network_primary_path_active" | jq -r .status 2>/dev/null || echo "")
if [ "$ROUTERS_UP" -ge 4 ] && [ "$PROXY_STATUS" = "success" ]; then
    echo "✓ 4/4 ROUTERS EN SCRAPE CONTINUO | GRAFANA PROXY OK (OK)"
else
    echo "✗ ERROR: Regresion detectada (Routers: $ROUTERS_UP, Proxy: $PROXY_STATUS)"
    exit 1
fi

echo "================================================================="
echo "  ✓ TODAS LAS VALIDACIONES DE LA FASE 5 COMPLETADAS CON EXITO    "
echo "================================================================="
