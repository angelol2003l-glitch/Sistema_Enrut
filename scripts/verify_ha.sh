#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/verify_common.sh"
running r1
running r2
running r-acceso
for node in r1 r2 r-acceso; do
    docker exec "$node" pgrep -f '^python3 /usr/local/bin/remediation_server.py$' >/dev/null \
        || fail "Agente ausente en $node"
    body="$(docker exec nms curl --fail --silent --show-error --max-time 5 "http://$node:5000/health")" \
        || fail "Agente sin respuesta en $node"
    jq -e '.status == "online"' >/dev/null <<<"$body" || fail "Salud del agente $node"
    ok "Agente de remediacion $node"
done
docker exec r-acceso pgrep -f '^(bash|/bin/sh) /usr/local/bin/sla_tracker.sh$' >/dev/null \
    || fail "SLA tracker ausente"
ok "SLA tracker activo"
route="$(docker exec r-acceso ip -4 route show default)"
case "$route" in
    "default via 192.168.21.1 dev eth1"*) primary=1; backup=0 ;;
    "default via 192.168.22.1 dev eth2"*) primary=0; backup=1 ;;
    *) fail "Ruta inesperada: $route" ;;
esac
[[ "$(wc -l <<<"$route")" -eq 1 ]] || fail "Multiples rutas por defecto"
metric 'network_primary_path_active' "all(.[]; . == $primary)"
metric 'network_backup_path_active' "all(.[]; . == $backup)"
metric 'network_failover_state{router="r-acceso"}' "all(.[]; . == $backup)"
metric 'sum(network_failovers_total)' 'all(.[]; . >= 0)'
metric 'sum(network_autoheal_total)' 'all(.[]; . >= 0)'
metric 'sum(network_autoheal_success_total)' 'all(.[]; . >= 0)'
metric 'sum(network_autoheal_active)' 'all(.[]; . >= 0)'
metric 'network_mttr_current_seconds' 'all(.[]; . >= 0)'
metric 'sum(network_mttr_seconds_count)' 'all(.[]; . >= 0)'
dashboard
router_targets
ok "HA verificada; ruta real y telemetria coinciden"
