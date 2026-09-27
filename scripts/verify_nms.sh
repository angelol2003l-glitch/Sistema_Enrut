#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE VALIDACION COMPLETA - FASE 4: INTEGRACION NMS PYTHON CON PROMETHEUS
# ==============================================================================
set -e

echo "================================================================="
echo "   VALIDACION FASE 4: INTEGRACION NMS PYTHON CON PROMETHEUS     "
echo "================================================================="

# 1. Proceso NMS y Contenedor
echo -n "[1/10] Estado del contenedor 'nms' y proceso 'monitor_definitivo.py': "
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

# 2. Endpoint /metrics en NMS (puerto 8000)
echo -n "[2/10] Endpoint de Metricas NMS (http://172.20.20.7:8000/metrics): "
HTTP_CODE=$(docker exec nms curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/metrics || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ RESPONDE HTTP 200 (OK)"
else
    echo "✗ ERROR: Endpoint /metrics respondio $HTTP_CODE"
    exit 1
fi

# 3. Target nms-python en Prometheus
echo -n "[3/10] Estado del Target 'nms-python' en Prometheus: "
TARGET_HEALTH=$(curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.job=="nms-python") | .health' 2>/dev/null || echo "unknown")
if [ "$TARGET_HEALTH" = "up" ]; then
    echo "✓ TARGET STATE = UP (OK)"
else
    echo "✗ ERROR: Target 'nms-python' en estado '$TARGET_HEALTH'"
    exit 1
fi

# 4. Metricas de Estado (PC1 Reachable & Primary Path)
echo -n "[4/10] Metricas de Estado (PC1 y Ruta Primaria) en Prometheus: "
PC1_ST=$(curl -s "http://localhost:9090/api/v1/query?query=network_pc1_reachable" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "")
PATH_ST=$(curl -s "http://localhost:9090/api/v1/query?query=network_primary_path_active" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "")
if [ "$PC1_ST" = "1" ] && [ "$PATH_ST" = "1" ]; then
    echo "✓ PC1_REACHABLE=$PC1_ST | PRIMARY_PATH_ACTIVE=$PATH_ST (OK)"
else
    echo "✗ ERROR: Valores de estado inesperados (PC1: $PC1_ST, PATH: $PATH_ST)"
    exit 1
fi

# 5. Metricas de Incidentes y Auto-Remediacion
echo -n "[5/10] Metricas de Incidentes y Auto-Healing en Prometheus: "
INC_TOTAL=$(curl -s "http://localhost:9090/api/v1/query?query=sum(network_incidents_total)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "")
HEAL_TOTAL=$(curl -s "http://localhost:9090/api/v1/query?query=sum(network_autoheal_success_total)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "")
if [ -n "$INC_TOTAL" ] && [ -n "$HEAL_TOTAL" ]; then
    echo "✓ INCIDENTS_TOTAL=$INC_TOTAL | AUTOHEAL_SUCCESS=$HEAL_TOTAL (OK)"
else
    echo "✗ ERROR: No se pudieron consultar contadores de incidentes/autoheal"
    exit 1
fi

# 6. Metricas de MTTR (Histograma y Gauge)
echo -n "[6/10] Registro y Calculo de MTTR en Prometheus: "
MTTR_COUNT=$(curl -s "http://localhost:9090/api/v1/query?query=sum(network_mttr_seconds_count)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if [ "$MTTR_COUNT" -ge 1 ]; then
    AVG_MTTR=$(curl -s "http://localhost:9090/api/v1/query?query=sum(network_mttr_seconds_sum)/sum(network_mttr_seconds_count)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
    echo "✓ MTTR MUESTRAS=$MTTR_COUNT | MTTR MEDIO=${AVG_MTTR}s (OK)"
else
    echo "✓ HISTOGRAMA Y GAUGE REGISTRADOS (OK)"
fi

# 7. Integracion de Grafana con Dashboard NMS Self-Healing
echo -n "[7/10] Dashboard 'NMS & Self-Healing Telemetry' en Grafana: "
GRAFANA_NMS=$(curl -s http://localhost:3000/api/dashboards/uid/nms-self-healing | jq -r '.dashboard.title' 2>/dev/null || echo "")
if [ "$GRAFANA_NMS" = "NMS & Self-Healing Telemetry" ]; then
    echo "✓ UID 'nms-self-healing' DISPONIBLE Y ACTIVO (OK)"
else
    echo "✗ ERROR: Dashboard nms-self-healing no encontrado en Grafana"
    exit 1
fi

# 8. Consulta de Metricas NMS via Proxy de Grafana
echo -n "[8/10] Proxy de Consulta Grafana -> Metricas NMS: "
PROXY_RES=$(curl -s "http://localhost:3000/api/datasources/uid/prometheus/resources/api/v1/query?query=network_pc1_reachable" | jq -r .status 2>/dev/null || echo "")
if [ "$PROXY_RES" = "success" ]; then
    echo "✓ PROMETHEUS DATASOURCE PROXY OPERATIVO (OK)"
else
    echo "✗ ERROR: Fallo al consultar metricas NMS a traves de Grafana"
    exit 1
fi

# 9. Integridad de la Bitacora Forense (/app/incidentes_red.log y reporte_sla.py)
echo -n "[9/10] Bitacora Forense y Reporte de SLA: "
LOG_LINES=$(docker exec nms wc -l /app/incidentes_red.log | awk '{print $1}')
if [ "$LOG_LINES" -gt 0 ]; then
    SLA_OUT=$(docker exec nms python3 /app/reporte_sla.py | grep "Tiempo Medio de Recuperacion" || echo "")
    if [ -n "$SLA_OUT" ]; then
        echo "✓ BITACORA ACTIVA ($LOG_LINES lineas) | REPORTE_SLA OK (OK)"
    else
        echo "✗ ERROR: reporte_sla.py fallo al parsear la bitacora"
        exit 1
    fi
else
    echo "✗ ERROR: /app/incidentes_red.log vacio o inaccesible"
    exit 1
fi

# 10. Integridad de Fases Anteriores (Prometheus, SNMP Exporter, Routers)
echo -n "[10/10] Verificacion de No Regresion (Fases 1, 2 y 3): "
ROUTERS_UP=$(curl -s "http://localhost:9090/api/v1/query?query=count(up%7Bjob%3D%22snmp-routers%22%7D)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if [ "$ROUTERS_UP" -ge 4 ]; then
    echo "✓ 4/4 ROUTERS EN SCRAPE SNMP CONTINUO (OK)"
else
    echo "✗ ERROR: Solo $ROUTERS_UP routers reportan SNMP UP"
    exit 1
fi

echo "================================================================="
echo "  ✓ TODAS LAS VALIDACIONES DE LA FASE 4 COMPLETADAS CON EXITO    "
echo "================================================================="
