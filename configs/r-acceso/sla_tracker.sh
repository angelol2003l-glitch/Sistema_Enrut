#!/bin/sh
# ==============================================================================
# Controlador de Enrutamiento Dinamico (SDN / NetDevOps Agent) - R-ACCESO
#
# Filosofia Zero-Config / Dynamic Route Injection:
# - El router NO posee rutas de contingencia estaticas de antemano.
# - Al detectar la falla del enlace primario (R1), el controlador crea e
#   inyecta en tiempo de ejecucion la ruta de salida via R2.
# - Al restablecerse R1, retira la ruta inyectada y restaura la ruta primaria.
# ==============================================================================

TARGET="192.168.21.1"   # R1 (Camino Primario)
BACKUP="192.168.22.1"   # R2 (Camino Respaldo Dinamico)
LOG_FILE="/var/log/sla_tracker.log"
STATE="UP"

# 1. Asegurar estado inicial estricto: CERO rutas hacia R2 preconfiguradas
while ip route del default 2>/dev/null; do :; done
ip route add default via $TARGET dev eth1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SDN-INIT] Controlador Dinamico iniciado. Estado nominal: Solo ruta primaria via $TARGET (eth1). Sin rutas hacia R2." >> "$LOG_FILE"

while true; do
    # Prueba de enlace activo hacia R1
    if ping -c 1 -W 1 -I eth1 "$TARGET" > /dev/null 2>&1; then
        if [ "$STATE" != "UP" ]; then
            # --- FASE DE PREEMPCON Y RESTAURACION ---
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SDN-RESTORE] R1 ($TARGET) en linea. Retirando ruta inyectada y restaurando R1 (dev eth1)..." >> "$LOG_FILE"
            while ip route del default 2>/dev/null; do :; done
            ip route add default via $TARGET dev eth1
            STATE="UP"
        fi
    else
        # Verificacion rapida de confirmacion de caida (200ms)
        sleep 0.2
        if ! ping -c 1 -W 1 -I eth1 "$TARGET" > /dev/null 2>&1; then
            if [ "$STATE" != "DOWN" ]; then
                # --- FASE DE INYECCION DINAMICA (SDN FAILOVER) ---
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SDN-INJECT] ¡Falla en R1 ($TARGET) confirmada! Inyectando dinamicamente ruta hacia R2 ($BACKUP dev eth2)..." >> "$LOG_FILE"
                while ip route del default 2>/dev/null; do :; done
                ip route add default via $BACKUP dev eth2
                STATE="DOWN"
            fi
        fi
    fi
    sleep 1
done
