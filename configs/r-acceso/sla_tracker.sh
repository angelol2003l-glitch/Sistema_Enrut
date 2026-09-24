#!/bin/sh
TARGET="192.168.21.1"
BACKUP="192.168.22.1"
STATE="UP"

# Ensure initial routes
ip route replace default via $BACKUP dev eth2 metric 10
ip route replace default via $TARGET dev eth1 metric 1

echo "[$(date)] SLA Tracker iniciado en R-ACCESO (monitoreando $TARGET)..." >> /var/log/sla_tracker.log

while true; do
    if ping -c 1 -W 1 -I eth1 "$TARGET" > /dev/null 2>&1; then
        if [ "$STATE" != "UP" ]; then
            echo "[$(date)] [TRACK-UP] Restaurando ruta primaria via $TARGET" >> /var/log/sla_tracker.log
            ip route replace default via $TARGET dev eth1 metric 1
            STATE="UP"
        fi
    else
        sleep 1
        if ! ping -c 1 -W 1 -I eth1 "$TARGET" > /dev/null 2>&1; then
            if [ "$STATE" != "DOWN" ]; then
                echo "[$(date)] [TRACK-DOWN] Falla en $TARGET detectada! Conmutando a $BACKUP" >> /var/log/sla_tracker.log
                ip route del default via $TARGET dev eth1 2>/dev/null || true
                STATE="DOWN"
            fi
        fi
    fi
    sleep 2
done
