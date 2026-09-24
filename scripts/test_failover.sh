#!/bin/bash
echo "=========================================="
echo "   TEST DE CONMUTACION Y RESILIENCIA L3   "
echo "=========================================="

echo "1. Estado nominal: Ping continuo desde PC1 a 8.8.8.8..."
docker exec pc1 ping -c 3 8.8.8.8

echo ""
echo "2. Cortando enlace primario R1 <-> R-ACCESO (eth3 en R1 down)..."
docker exec r1 ip link set eth3 down
sleep 4

echo ""
echo "3. Verificando enrutamiento conmutado en R-ACCESO:"
docker exec r-acceso ip route show | grep default

echo ""
echo "4. Validando continuidad del trafico desde PC1 (0% perdida esperada):"
docker exec pc1 ping -c 3 8.8.8.8

echo ""
echo "5. Restaurando enlace primario (eth3 en R1 up)..."
docker exec r1 ip link set eth3 up
sleep 4

echo ""
echo "6. Bitacora Forense del NMS (/app/incidentes_red.log):"
echo "------------------------------------------------------"
docker exec nms tail -n 10 /app/incidentes_red.log
echo "=========================================="
