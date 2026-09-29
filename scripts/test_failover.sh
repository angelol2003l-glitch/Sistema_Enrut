#!/usr/bin/env bash
# Comprueba R1 -> R2 -> R1. Pausa solo el agente de R1 durante la falla
# controlada; EXIT/INT/TERM restauran el enlace y reanudan el mismo proceso.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/verify_common.sh"
STATE_TIMEOUT="${FAILOVER_TIMEOUT:-30}"
TELEMETRY_TIMEOUT="${FAILOVER_TELEMETRY_TIMEOUT:-60}"
HOLD_SECONDS="${FAILOVER_HOLD_SECONDS:-15}"
PROBE_IP="${FAILOVER_PROBE_IP:-8.8.8.8}"
for value in "$STATE_TIMEOUT" "$TELEMETRY_TIMEOUT" "$HOLD_SECONDS"; do
    [[ "$value" =~ ^[1-9][0-9]*$ ]] && (( value <= 120 )) || fail "Timeout debe estar entre 1 y 120 segundos"
done
command -v flock >/dev/null || fail "Falta flock"
command -v timeout >/dev/null || fail "Falta timeout"
exec 9>/tmp/sistema-enrut-failover.lock
flock -n 9 || fail "Ya hay una prueba de failover en curso"
log() { printf '%s %s\n' "$(date --iso-8601=seconds)" "$*"; }
route_is() {
    local route
    route="$(timeout 5 docker exec r-acceso ip -4 route show default)" || return 1
    [[ "$(wc -l <<<"$route")" -eq 1 && "$route" == "default via $1 dev $2"* ]]
}
wait_route() {
    local deadline=$((SECONDS + STATE_TIMEOUT))
    while (( SECONDS < deadline )); do
        if route_is "$1" "$2"; then
            log "ESTADO OBSERVADO: $3 | via $1 dev $2"
            return 0
        fi
        sleep 1
    done
    log "ERROR: timeout esperando $3" >&2
    return 1
}
telemetry_is() {
    local metrics
    metrics="$(timeout 5 docker exec nms curl -fsS http://localhost:8000/metrics)" || return 1
    grep -qFx "network_primary_path_active $1.0" <<<"$metrics" &&
        grep -qFx "network_backup_path_active $2.0" <<<"$metrics" &&
        grep -qFx "network_failover_state{router=\"r-acceso\"} $2.0" <<<"$metrics"
}
wait_telemetry() {
    local deadline=$((SECONDS + TELEMETRY_TIMEOUT))
    while (( SECONDS < deadline )); do
        if telemetry_is "$1" "$2"; then
            log "TELEMETRIA OBSERVADA: $3"
            return 0
        fi
        sleep 1
    done
    log "ERROR: timeout esperando telemetria de $3" >&2
    return 1
}
probe() {
    timeout 12 docker exec pc1 ping -c 3 -W 2 "$PROBE_IP" \
        || fail "PC1 no alcanza $PROBE_IP en $1"
    log "Conectividad PC1 confirmada en $1"
}
paused=0
changed=0
agent_pid=""
cleanup() {
    local result=$? restore_error=0
    trap - EXIT INT TERM
    set +e
    if (( changed )); then
        timeout 10 docker exec r1 ip link set eth3 up || restore_error=1
    fi
    if (( paused )); then
        timeout 10 docker exec r1 kill -CONT "$agent_pid" || restore_error=1
    fi
    if (( changed )); then
        wait_route 192.168.21.1 eth1 "R1 restaurado al salir" || restore_error=1
    fi
    if (( restore_error )); then
        log "ERROR: revisar manualmente enlace eth3 y agente de R1" >&2
        result=1
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

running r1
running r-acceso
running pc1
running nms
route_is 192.168.21.1 eth1 || fail "La prueba requiere R1 como ruta inicial"
timeout 5 docker exec r1 ip -j link show eth3 | jq -e '.[0].flags | index("UP") != null' >/dev/null \
    || fail "eth3 debe comenzar UP"
agent_pid="$(timeout 5 docker exec r1 pgrep -f '^python3 /usr/local/bin/remediation_server.py$')"
[[ "$agent_pid" =~ ^[0-9]+$ ]] || fail "Se esperaba un unico agente de R1"
timeout 5 docker exec r1 python3 -c 'import urllib.request; urllib.request.urlopen("http://localhost:5000/health",timeout=3)' \
    || fail "Agente de R1 no responde antes de la prueba"
wait_route 192.168.21.1 eth1 "R1 principal"
wait_telemetry 1 0 "R1 principal"
probe "R1 principal"
paused=1
timeout 5 docker exec r1 kill -STOP "$agent_pid"
changed=1
timeout 5 docker exec r1 ip link set eth3 down
wait_route 192.168.22.1 eth2 "R2 respaldo activo"
wait_telemetry 0 1 "R2 respaldo activo"
probe "R2 respaldo"
sleep "$HOLD_SECONDS"
route_is 192.168.22.1 eth2 || fail "R2 dejo de ser la ruta durante la prueba"
telemetry_is 0 1 || fail "La telemetria dejo de indicar R2 durante la falla sostenida"
timeout 5 docker exec r1 ip link set eth3 up
timeout 5 docker exec r1 kill -CONT "$agent_pid"
paused=0
wait_route 192.168.21.1 eth1 "Recuperacion de R1"
wait_telemetry 1 0 "Recuperacion de R1"
probe "R1 recuperado"
timeout 5 docker exec r1 python3 -c 'import urllib.request; urllib.request.urlopen("http://localhost:5000/health",timeout=3)' \
    || fail "Agente de R1 no responde tras recuperacion"
log "PRUEBA CORRECTA: R1 principal -> R2 respaldo activo -> recuperacion de R1"
