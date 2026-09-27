#!/usr/bin/env bash
set -euo pipefail

echo "================================================================="
echo "   VALIDACION FASE 3: GRAFANA + DASHBOARDS DE OBSERVABILIDAD     "
echo "================================================================="

# 1. Verificar estado de contenedores
echo -n "[1/10] Estado de 'grafana': "
if [ "$(docker inspect -f '{{.State.Running}}' grafana 2>/dev/null)" = "true" ]; then
    echo "✓ RUNNING (OK)"
else
    echo "✗ ERROR: Contenedor grafana no esta corriendo"
    exit 1
fi

echo -n "[2/10] Estado de 'prometheus': "
if [ "$(docker inspect -f '{{.State.Running}}' prometheus 2>/dev/null)" = "true" ]; then
    echo "✓ RUNNING (OK)"
else
    echo "✗ ERROR: Contenedor prometheus no esta corriendo"
    exit 1
fi

echo -n "[3/10] Estado de 'snmp-exporter': "
if [ "$(docker inspect -f '{{.State.Running}}' snmp-exporter 2>/dev/null)" = "true" ]; then
    echo "✓ RUNNING (OK)"
else
    echo "✗ ERROR: Contenedor snmp-exporter no esta corriendo"
    exit 1
fi

# 2. Endpoint de Salud de Grafana
echo -n "[4/10] Endpoint de Salud Grafana (http://localhost:3000/api/health): "
HEALTH_RES=$(curl -s http://localhost:3000/api/health | jq -r .database 2>/dev/null || echo "error")
if [ "$HEALTH_RES" = "ok" ]; then
    echo "✓ DATABASE OK (HTTP 200)"
else
    echo "✗ ERROR: Grafana health check fallo ($HEALTH_RES)"
    exit 1
fi

# 3. Validar Provisioning de Data Source Prometheus
echo -n "[5/10] Data Source Prometheus aprovisionado en Grafana: "
DS_NAME=$(curl -s http://localhost:3000/api/datasources | jq -r '.[] | select(.name=="Prometheus") | .type' 2>/dev/null || echo "")
if [ "$DS_NAME" = "prometheus" ]; then
    echo "✓ PROMETHEUS CONFIGURADO Y CONECTADO (OK)"
else
    echo "✗ ERROR: Data Source Prometheus no encontrado"
    exit 1
fi

# 4. Validar Proxy de Consulta de Grafana hacia Prometheus
echo -n "[6/10] Proxy de Consulta Grafana -> Prometheus: "
PROXY_STATUS=$(curl -s "http://localhost:3000/api/datasources/uid/prometheus/resources/api/v1/query?query=up" | jq -r .status 2>/dev/null || echo "")
if [ "$PROXY_STATUS" = "success" ]; then
    echo "✓ CONSULTA PROMETHEUS VIA GRAFANA EXITOSA (OK)"
else
    echo "✗ ERROR: Fallo al consultar Prometheus desde Grafana"
    exit 1
fi

# 5. Validar Dashboards Aprovisionados
echo -n "[7/10] Dashboards aprovisionados en Grafana: "
DB_COUNT=$(curl -s http://localhost:3000/api/search | jq -r '[.[] | select(.type=="dash-db")] | length' 2>/dev/null || echo "0")
if [ "$DB_COUNT" -ge 3 ]; then
    echo "✓ $DB_COUNT DASHBOARDS LISTOS Y PROVISIONADOS (OK)"
else
    echo "✗ ERROR: Se esperaban al menos 3 dashboards, encontrados: $DB_COUNT"
    exit 1
fi

# 6. Validar Dashboard de Network Overview
echo -n "[8/10] Verificando Dashboard 'Network NOC Overview': "
UID_OVERVIEW=$(curl -s http://localhost:3000/api/dashboards/uid/network-overview | jq -r .dashboard.uid 2>/dev/null || echo "")
if [ "$UID_OVERVIEW" = "network-overview" ]; then
    echo "✓ UID 'network-overview' FUNCIONAL (OK)"
else
    echo "✗ ERROR: Dashboard network-overview no responde"
    exit 1
fi

# 7. Validar Dashboard de Interfaces y Disponibilidad
echo -n "[9/10] Verificando Dashboards 'Interfaces Detail' y 'Disponibilidad': "
UID_IFACES=$(curl -s http://localhost:3000/api/dashboards/uid/interfaces-detail | jq -r .dashboard.uid 2>/dev/null || echo "")
UID_AVAIL=$(curl -s http://localhost:3000/api/dashboards/uid/network-availability | jq -r .dashboard.uid 2>/dev/null || echo "")
if [ "$UID_IFACES" = "interfaces-detail" ] && [ "$UID_AVAIL" = "network-availability" ]; then
    echo "✓ AMBOS DASHBOARDS ACTIVOS (OK)"
else
    echo "✗ ERROR en dashboards adicionales ($UID_IFACES / $UID_AVAIL)"
    exit 1
fi

# 8. Integridad de la infraestructura existente
echo -n "[10/10] Integridad del laboratorio de red Containerlab: "
FAILED_NODES=0
for node in r1 r2 r-acceso r-gestion nms pc1; do
    if [ "$(docker inspect -f '{{.State.Running}}' $node 2>/dev/null)" != "true" ]; then
        echo -n "[$node: CAIDO] "
        FAILED_NODES=$((FAILED_NODES + 1))
    fi
done

if [ "$FAILED_NODES" -eq 0 ]; then
    echo "✓ TODOS LOS NODOS DE RED SIGUEN OPERATIVOS (OK)"
else
    echo "✗ ERROR: $FAILED_NODES nodos afectados"
    exit 1
fi

echo "================================================================="
echo "  ✓ TODAS LAS VALIDACIONES DE LA FASE 3 COMPLETADAS CON EXITO    "
echo "================================================================="
