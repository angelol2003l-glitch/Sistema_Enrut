#!/bin/bash
echo "=========================================="
echo "   AUDITORIA SNMP DESDE EL NMS"
echo "=========================================="
for ip in 192.168.10.1 192.168.11.2 192.168.12.2 192.168.21.2; do
    echo -n "Consultando $ip (sysName): "
    docker exec nms snmpget -v 2c -c redes2026 -Oqv $ip 1.3.6.1.2.1.1.5.0
done

echo ""
echo "Consultando ipRouteNextHop activo en R-ACCESO (1.3.6.1.2.1.4.21.1.7.0.0.0.0):"
docker exec nms snmpget -v 2c -c redes2026 -Oqv 192.168.21.2 1.3.6.1.2.1.4.21.1.7.0.0.0.0 || docker exec nms snmpget -v 2c -c redes2026 -Oqv 192.168.22.2 1.3.6.1.2.1.4.21.1.7.0.0.0.0
echo "=========================================="
