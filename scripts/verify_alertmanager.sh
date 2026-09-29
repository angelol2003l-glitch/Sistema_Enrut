#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/verify_common.sh"
running alertmanager
docker exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml >/dev/null \
    || fail "Configuracion de Alertmanager invalida"
ok "Configuracion de Alertmanager"
curl --fail --silent --show-error --max-time 10 "$ALERTMANAGER_URL/-/ready" >/dev/null
assert_json "$ALERTMANAGER_URL/api/v2/status" '.versionInfo.version | length > 0' "API v2 de Alertmanager"
assert_json "$PROMETHEUS_URL/api/v1/alertmanagers" \
    '.status == "success" and (.data.activeAlertmanagers | length > 0)' "Prometheus -> Alertmanager"
assert_json "$PROMETHEUS_URL/api/v1/rules" \
    '.status == "success" and ([.data.groups[].rules[]] | length > 0) and
     all(.data.groups[].rules[]; .health == "ok")' "Reglas actuales cargadas y evaluadas"
assert_json "$GRAFANA_URL/api/datasources/uid/alertmanager" \
    '.uid == "alertmanager" and .type == "alertmanager"' "Fuente Alertmanager en Grafana"
router_targets
ok "Alertmanager verificado"
