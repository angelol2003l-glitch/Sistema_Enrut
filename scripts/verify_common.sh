#!/usr/bin/env bash
# Funciones compartidas por los verificadores del laboratorio actual.
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
ALERTMANAGER_URL="${ALERTMANAGER_URL:-http://localhost:9093}"
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
ok() { printf '[OK] %s\n' "$*"; }
for dependency in docker curl jq; do
    command -v "$dependency" >/dev/null || fail "Falta $dependency"
done
json_get() { curl --fail --silent --show-error --connect-timeout 3 --max-time 10 "$1"; }
assert_json() {
    local body
    body="$(json_get "$1")" || fail "No responde $1"
    jq -e "$2" >/dev/null <<<"$body" || fail "$3"
    ok "$3"
}
running() {
    [[ "$(docker inspect -f '{{.State.Running}}' "$1")" == true ]] || fail "$1 no esta activo"
    ok "Contenedor $1"
}
query() {
    curl --fail --silent --show-error --connect-timeout 3 --max-time 10 \
        --get --data-urlencode "query=$1" "$PROMETHEUS_URL/api/v1/query"
}
metric() {
    local response values
    response="$(query "$1")" || fail "Fallo consulta: $1"
    values="$(jq -ce '. | select(.status == "success") | .data.result |
        select(length > 0) | map(.value[1] | tonumber) |
        select(all(.[]; . != null and . > -1e308 and . < 1e308))' <<<"$response")" \
        || fail "Metrica ausente o no numerica: $1"
    jq -e "$2" >/dev/null <<<"$values" || fail "Valor inesperado: $1 = $values"
    ok "$1 = $values"
}
dashboard() {
    local uid body
    uid="$(jq -er '.uid' "$REPO_ROOT/monitoring/grafana/dashboards/noc_l3_ha.json")"
    body="$(json_get "$GRAFANA_URL/api/dashboards/uid/$uid")" || fail "Dashboard $uid"
    jq -e --arg uid "$uid" '.dashboard.uid == $uid and
        (.dashboard.panels | length > 0)' >/dev/null <<<"$body" || fail "Dashboard invalido: $uid"
    ok "Dashboard provisionado: $uid"
}
router_targets() {
    assert_json "$PROMETHEUS_URL/api/v1/targets" \
        '[.data.activeTargets[] | select(.labels.job == "snmp-routers")] |
         length == 4 and all(.[]; .health == "up")' "Cuatro targets SNMP activos"
}
