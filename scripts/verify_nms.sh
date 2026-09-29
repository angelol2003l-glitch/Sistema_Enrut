#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/verify_common.sh"
running nms
docker exec nms pgrep -f '^python3 /app/monitor_definitivo.py$' >/dev/null || fail "Monitor NMS ausente"
docker exec nms curl --fail --silent --show-error --max-time 10 http://localhost:8000/metrics >/dev/null \
    || fail "Endpoint NMS /metrics"
ok "Proceso NMS y endpoint /metrics"
assert_json "$PROMETHEUS_URL/api/v1/targets" \
    '[.data.activeTargets[] | select(.labels.job == "nms-python")] |
     length == 1 and all(.[]; .health == "up")' "Target nms-python activo"
metric 'network_pc1_reachable' 'all(.[]; . == 1)'
metric 'network_primary_path_active + network_backup_path_active' 'all(.[]; . == 1)'
metric 'sum(network_incidents_total)' 'all(.[]; . >= 0)'
metric 'sum(network_autoheal_success_total)' 'all(.[]; . >= 0)'
metric 'sum(network_mttr_seconds_count)' 'all(.[]; . >= 0)'
metric 'network_mttr_current_seconds' 'all(.[]; . >= 0)'
dashboard
assert_json "$GRAFANA_URL/api/datasources/uid/prometheus/resources/api/v1/query?query=network_pc1_reachable" \
    '.status == "success" and (.data.result | length > 0)' "Telemetria NMS desde Grafana"
# Un laboratorio recien iniciado puede no tener incidentes ni bitacora todavia.
if docker exec nms test -f /app/incidentes_red.log; then
    docker exec nms python3 /app/reporte_sla.py >/dev/null || fail "Reporte SLA"
    ok "Bitacora y reporte SLA"
else
    ok "Sin bitacora todavia: no se exige un incidente previo"
fi
router_targets
ok "NMS verificado"
