#!/usr/bin/env bash
set -euo pipefail

echo "================================================================="
echo "   VALIDACION FASE 2: SNMP EXPORTER & PROMETHEUS INTEGRATION     "
echo "================================================================="

# 1. Estado de los contenedores
echo -n "[1/10] Estado de 'snmp-exporter': "
if [ "$(docker inspect -f '{{.State.Running}}' snmp-exporter 2>/dev/null)" = "true" ]; then
    echo "✓ RUNNING (OK)"
else
    echo "✗ ERROR: Contenedor snmp-exporter no esta corriendo"
    exit 1
fi

echo -n "[2/10] Estado de 'prometheus': "
if [ "$(docker inspect -f '{{.State.Running}}' prometheus 2>/dev/null)" = "true" ]; then
    echo "✓ RUNNING (OK)"
else
    echo "✗ ERROR: Contenedor prometheus no esta corriendo"
    exit 1
fi

# 2. Validar HTTP Endpoint de SNMP Exporter
echo -n "[3/10] Endpoint HTTP snmp-exporter (puerto 9116): "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9116/ || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ RESPONDE HTTP 200 (OK)"
else
    echo "✗ ERROR: Codigo HTTP $HTTP_CODE"
    exit 1
fi

# 3. Consultas directas via SNMP Exporter hacia cada router
echo -n "[4/10] Consulta SNMP directa a R1 (sysName): "
R1_SYS=$(curl -s "http://localhost:9116/snmp?target=r1&module=router_ha&auth=redes2026" | grep '^sysName{sysName="r1"}' || true)
if [ -n "$R1_SYS" ]; then
    echo "✓ sysName='r1' DETECTADO (OK)"
else
    echo "✗ ERROR al consultar R1"
    exit 1
fi

echo -n "[5/10] Consulta SNMP directa a R2 (sysName): "
R2_SYS=$(curl -s "http://localhost:9116/snmp?target=r2&module=router_ha&auth=redes2026" | grep '^sysName{sysName="r2"}' || true)
if [ -n "$R2_SYS" ]; then
    echo "✓ sysName='r2' DETECTADO (OK)"
else
    echo "✗ ERROR al consultar R2"
    exit 1
fi

echo -n "[6/10] Consulta SNMP directa a R-ACCESO (sysName): "
RACC_SYS=$(curl -s "http://localhost:9116/snmp?target=r-acceso&module=router_ha&auth=redes2026" | grep '^sysName{sysName="r-acceso"}' || true)
if [ -n "$RACC_SYS" ]; then
    echo "✓ sysName='r-acceso' DETECTADO (OK)"
else
    echo "✗ ERROR al consultar R-ACCESO"
    exit 1
fi

echo -n "[7/10] Consulta SNMP directa a R-GESTION (sysName): "
RGEST_SYS=$(curl -s "http://localhost:9116/snmp?target=r-gestion&module=router_ha&auth=redes2026" | grep '^sysName{sysName="r-gestion"}' || true)
if [ -n "$RGEST_SYS" ]; then
    echo "✓ sysName='r-gestion' DETECTADO (OK)"
else
    echo "✗ ERROR al consultar R-GESTION"
    exit 1
fi

# 4. Validar Targets de SNMP Exporter en Prometheus
echo -n "[8/10] Estado de los 4 targets en Prometheus (job=snmp-routers): "
ROUTER_UP_COUNT=$(curl -s http://localhost:9090/api/v1/targets | jq -r '[.data.activeTargets[] | select(.labels.job=="snmp-routers" and .health=="up")] | length')
if [ "$ROUTER_UP_COUNT" -eq 4 ]; then
    echo "✓ 4/4 TARGETS EN ESTADO UP (OK)"
else
    echo "✗ ERROR: Solo $ROUTER_UP_COUNT/4 targets estan UP"
    exit 1
fi

# 5. Validar Metricas PromQL
echo -n "[9/10] Consulta PromQL: ifOperStatus en Prometheus: "
IF_COUNT=$(curl -s "http://localhost:9090/api/v1/query?query=ifOperStatus" | jq -r '.data.result | length')
if [ "$IF_COUNT" -gt 0 ]; then
    echo "✓ $IF_COUNT SERIES DE ifOperStatus RECIBIDAS (OK)"
else
    echo "✗ ERROR: No hay metricas de ifOperStatus en Prometheus"
    exit 1
fi

# 6. Validar que la infraestructura existente sigue viva
echo -n "[10/10] Integridad del laboratorio existente: "
FAILED_NODES=0
for node in r1 r2 r-acceso r-gestion nms pc1; do
    if [ "$(docker inspect -f '{{.State.Running}}' $node 2>/dev/null)" != "true" ]; then
        echo -n "[$node: CAIDO] "
        FAILED_NODES=$((FAILED_NODES + 1))
    fi
done

if [ "$FAILED_NODES" -eq 0 ]; then
    echo "✓ TODOS LOS NODOS DE RED OPERATIVOS (OK)"
else
    echo "✗ ERROR: $FAILED_NODES nodos afectados"
    exit 1
fi

# Limpieza de archivo scratch temporal si existe
rm -f /home/angelo/Sistema_Enrut/scratch_snmp.yml 2>/dev/null || true

echo "================================================================="
echo "  ✓ TODAS LAS VALIDACIONES DE LA FASE 2 COMPLETADAS CON EXITO    "
echo "================================================================="
