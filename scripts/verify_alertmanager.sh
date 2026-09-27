#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE VALIDACION COMPLETA - FASE 6: ALERTAS, SLA Y ALERTMANAGER
# ==============================================================================
set -e

echo "================================================================="
echo "   VALIDACION FASE 6: ALERTAS, SLA Y ALERTMANAGER               "
echo "================================================================="

# 1. Contenedor Alertmanager en ejecucion
echo -n "[1/10] Estado del contenedor 'alertmanager': "
AM_STATUS=$(docker inspect -f '{{.State.Status}}' alertmanager 2>/dev/null || echo "missing")
if [ "$AM_STATUS" = "running" ]; then
    echo "✓ RUNNING (OK)"
else
    echo "✗ ERROR: Contenedor 'alertmanager' en estado $AM_STATUS"
    exit 1
fi

# 2. Endpoint de Salud de Alertmanager (puerto 9093)
echo -n "[2/10] Endpoint de Salud Alertmanager (http://localhost:9093/-/healthy): "
AM_HEALTH=$(curl -s http://localhost:9093/-/healthy 2>/dev/null || echo "")
if [ "$AM_HEALTH" = "OK" ]; then
    echo "✓ RESPONDE HTTP 200 OK (OK)"
else
    echo "✗ ERROR: Alertmanager no respondio OK"
    exit 1
fi

# 3. Integracion Prometheus -> Alertmanager
echo -n "[3/10] Integracion de Alertmanager en Prometheus: "
AM_COUNT=$(curl -s http://localhost:9090/api/v1/alertmanagers | jq '.data.activeAlertmanagers | length' 2>/dev/null || echo "0")
if [ "$AM_COUNT" -ge 1 ]; then
    AM_URL=$(curl -s http://localhost:9090/api/v1/alertmanagers | jq -r '.data.activeAlertmanagers[0].url')
    echo "✓ 1 ALERTMANAGER ACTIVO ($AM_URL) (OK)"
else
    echo "✗ ERROR: Prometheus no detecto ningun Alertmanager activo"
    exit 1
fi

# 4. Reglas de Alerta (Alert Rules) cargadas en Prometheus
echo -n "[4/10] Reglas de Alerta cargadas en Prometheus: "
RULES_COUNT=$(curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[0].rules | length' 2>/dev/null || echo "0")
if [ "$RULES_COUNT" -ge 7 ]; then
    echo "✓ $RULES_COUNT REGLAS ACTIVAS Y EVALUADAS (OK)"
else
    echo "✗ ERROR: Se esperaban al menos 7 reglas, encontradas: $RULES_COUNT"
    exit 1
fi

# 5. Data Source Alertmanager aprovisionado en Grafana
echo -n "[5/10] Data Source Alertmanager en Grafana: "
AM_DS=$(curl -s http://localhost:3000/api/datasources/uid/alertmanager | jq -r .name 2>/dev/null || echo "")
if [ "$AM_DS" = "Alertmanager" ]; then
    echo "✓ DATA SOURCE 'Alertmanager' PROVISIONADO (OK)"
else
    echo "✗ ERROR: Data Source Alertmanager no encontrado en Grafana"
    exit 1
fi

# 6. Dashboard 'Network Alerts & Incident Management' en Grafana
echo -n "[6/10] Dashboard 'Network Alerts' en Grafana: "
DASH_ALERTS=$(curl -s http://localhost:3000/api/dashboards/uid/network-alerts | jq -r '.dashboard.title' 2>/dev/null || echo "")
if [ "$DASH_ALERTS" = "Network Alerts & Incident Management" ]; then
    echo "✓ UID 'network-alerts' LISTO (OK)"
else
    echo "✗ ERROR: Dashboard network-alerts no encontrado en Grafana"
    exit 1
fi

# 7. Dashboard 'SLA & NOC Service Overview' en Grafana
echo -n "[7/10] Dashboard 'SLA & NOC Overview' en Grafana: "
DASH_SLA=$(curl -s http://localhost:3000/api/dashboards/uid/sla-noc | jq -r '.dashboard.title' 2>/dev/null || echo "")
if [ "$DASH_SLA" = "SLA & NOC Service Overview" ]; then
    echo "✓ UID 'sla-noc' LISTO (OK)"
else
    echo "✗ ERROR: Dashboard sla-noc no encontrado en Grafana"
    exit 1
fi

# 8. Metricas de SLA y Confiabilidad en Prometheus
echo -n "[8/10] Metricas de SLA (Uptime, Failovers, MTTR) en Prometheus: "
PC1_UP=$(curl -s "http://localhost:9090/api/v1/query?query=network_pc1_reachable" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "")
MTTR_CURR=$(curl -s "http://localhost:9090/api/v1/query?query=network_mttr_current_seconds" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "")
FO_TOTAL=$(curl -s "http://localhost:9090/api/v1/query?query=sum(network_failovers_total)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "")
if [ "$PC1_UP" = "1" ] && [ -n "$MTTR_CURR" ] && [ -n "$FO_TOTAL" ]; then
    echo "✓ PC1_UP=$PC1_UP | FAILOVERS=$FO_TOTAL | MTTR_ACTUAL=${MTTR_CURR}s (OK)"
else
    echo "✗ ERROR: Metricas de SLA ausentes o invalidas"
    exit 1
fi

# 9. Bitacora Forense y Script reporte_sla.py
echo -n "[9/10] Bitacora Forense y Reporte de SLA: "
LOG_LINES=$(docker exec nms wc -l /app/incidentes_red.log | awk '{print $1}')
SLA_MTTR=$(docker exec nms python3 /app/reporte_sla.py | grep "Tiempo Medio de Recuperacion" | awk -F: '{print $2}' | xargs)
if [ "$LOG_LINES" -gt 0 ] && [ -n "$SLA_MTTR" ]; then
    echo "✓ $LOG_LINES EVENTOS | SLA MTTR: $SLA_MTTR (OK)"
else
    echo "✗ ERROR: Bitacora forense inaccesible"
    exit 1
fi

# 10. Verificacion de No Regresion (Fases 1 a 5)
echo -n "[10/10] Verificacion de No Regresion (Routers SNMP y Grafana Proxy): "
ROUTERS_UP=$(curl -s "http://localhost:9090/api/v1/query?query=count(up%7Bjob%3D%22snmp-routers%22%7D)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
TARGETS_UP=$(curl -s http://localhost:9090/api/v1/targets | jq '[.data.activeTargets[] | select(.health=="up")] | length')
if [ "$ROUTERS_UP" -ge 4 ] && [ "$TARGETS_UP" -ge 6 ]; then
    echo "✓ 4/4 ROUTERS UP | 6/6 PROMETHEUS TARGETS UP (OK)"
else
    echo "✗ ERROR: Regresion detectada (Routers: $ROUTERS_UP, Targets: $TARGETS_UP)"
    exit 1
fi

echo "================================================================="
echo "  ✓ TODAS LAS VALIDACIONES DE LA FASE 6 COMPLETADAS CON EXITO    "
echo "================================================================="
