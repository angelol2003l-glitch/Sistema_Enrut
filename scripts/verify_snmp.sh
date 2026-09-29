#!/usr/bin/env bash
set -euo pipefail

echo "AUDITORIA SNMP DESDE EL NMS"
for target in r-gestion r1 r2 r-acceso; do
    printf 'Consultando %s (sysName): ' "$target"
    docker exec nms sh -c 'community=$(cat /run/secrets/snmp_community) && exec snmpget -v2c -c "$community" -t 1 -r 0 -Oqv "$1" 1.3.6.1.2.1.1.5.0' sh "$target"
done

echo "Ruta activa observada en R-ACCESO:"
route=$(docker exec nms sh -c 'community=$(cat /run/secrets/snmp_community) && exec snmpget -v2c -c "$community" -t 1 -r 0 -Oqv r-acceso 1.3.6.1.4.1.8072.1.3.2.3.1.1.11.97.99.116.105.118.101.82.111.117.116.101')
route=${route#\"}
route=${route%\"}
case "$route" in
    'default via 192.168.21.1 dev eth1'*|'default via 192.168.22.1 dev eth2'*) echo "$route" ;;
    *) echo "Ruta inesperada: $route" >&2; exit 1 ;;
esac
