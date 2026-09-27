#!/usr/bin/env bash
set -euo pipefail

echo "================================================================="
echo "       VALIDACION FASE 1: PROMETHEUS - OBSERVABILIDAD LAB        "
echo "================================================================="

# 1. Verificar contenedor
echo -n "[1/7] Estado del contenedor 'prometheus': "
if [ "$(docker inspect -f '{{.State.Running}}' prometheus 2>/dev/null)" = "true" ]; then
    echo "✓ RUNNING (OK)"
else
    echo "✗ ERROR: Contenedor no esta corriendo"
    exit 1
fi

# 2. Validar configuracion con promtool dentro del contenedor
echo -n "[2/7] Validacion sintactica de prometheus.yml: "
if docker exec prometheus promtool check config /etc/prometheus/prometheus.yml >/dev/null 2>&1; then
    echo "✓ SINTAXIS VALIDA (OK)"
else
    echo "✗ ERROR: Configuracion invalida"
    docker exec prometheus promtool check config /etc/prometheus/prometheus.yml
    exit 1
fi

# 3. Validar Endpoint de Salud HTTP
echo -n "[3/7] Endpoint HTTP /-/healthy: "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/-/healthy || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ RESPONDE HTTP 200 (OK)"
else
    echo "✗ ERROR: Codigo HTTP $HTTP_CODE"
    exit 1
fi

# 4. Validar Endpoint de Readiness
echo -n "[4/7] Endpoint HTTP /-/ready: "
READY_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/-/ready || echo "000")
if [ "$READY_CODE" = "200" ]; then
    echo "✓ LISTO HTTP 200 (OK)"
else
    echo "✗ ERROR: Codigo HTTP $READY_CODE"
    exit 1
fi

# 5. Validar Target en API de Prometheus
echo -n "[5/7] Estado del target de auto-monitoreo: "
TARGET_HEALTH=$(curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.job=="prometheus") | .health' 2>/dev/null || echo "unknown")
if [ "$TARGET_HEALTH" = "up" ]; then
    echo "✓ TARGET STATE = UP (OK)"
else
    echo "✗ ERROR: Target no reporta UP (Estado: $TARGET_HEALTH)"
    exit 1
fi

# 6. Consultar Metrica 'up' via PromQL
echo -n "[6/7] Consulta PromQL (query=up): "
METRIC_VALUE=$(curl -s "http://localhost:9090/api/v1/query?query=up" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if [ "$METRIC_VALUE" = "1" ]; then
    echo "✓ METRICA up=1 (OK)"
else
    echo "✗ ERROR: Metrica no devolvio 1 (Valor: $METRIC_VALUE)"
    exit 1
fi

# 7. Validar que la infraestructura existente sigue viva (r1, r2, r-acceso, nms, pc1)
echo -n "[7/7] Integridad de la infraestructura existente: "
FAILED_NODES=0
for node in r1 r2 r-acceso r-gestion nms pc1; do
    if [ "$(docker inspect -f '{{.State.Running}}' $node 2>/dev/null)" != "true" ]; then
        echo -n "[$node: CAIDO] "
        FAILED_NODES=$((FAILED_NODES + 1))
    fi
done

if [ "$FAILED_NODES" -eq 0 ]; then
    echo "✓ TODOS LOS NODOS DE RED SIGUEN RUNNING (OK)"
else
    echo "✗ ERROR: $FAILED_NODES nodos afectados"
    exit 1
fi

echo "================================================================="
echo "       ✓ TODAS LAS VALIDACIONES DE FASE 1 COMPLETADAS CON EXITO   "
echo "================================================================="
