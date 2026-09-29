#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/verify_common.sh"
running grafana
assert_json "$GRAFANA_URL/api/health" '.database == "ok"' "Salud de Grafana"
assert_json "$GRAFANA_URL/api/datasources/uid/prometheus" \
    '.uid == "prometheus" and .type == "prometheus"' "Fuente Prometheus"
assert_json "$GRAFANA_URL/api/datasources/uid/alertmanager" \
    '.uid == "alertmanager" and .type == "alertmanager"' "Fuente Alertmanager"
assert_json "$GRAFANA_URL/api/datasources/uid/prometheus/resources/api/v1/query?query=up" \
    '.status == "success" and (.data.result | length > 0) and
     all(.data.result[]; .value[1] == "1")' "Consultas Grafana -> Prometheus"
dashboard
ok "Grafana verificado"
