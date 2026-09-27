# Matriz de Comportamiento de Fallas y Auto-Recuperación por Interfaz
**Laboratorio de Alta Disponibilidad L3 con FRR, IP SLA y Self-Healing NetDevOps**

Este documento detalla qué ocurre exactamente en la red, en el tráfico de usuario (PC1) y en el sistema de telemetría/Grafana cuando se apaga cada una de las interfaces de la topología.

---

## 1. Mapa de Enlaces y Topología de Red

```mermaid
flowchart TD
    subgraph Plano_Gestion["Plano de Gestión OOB (Out-of-Band)"]
        NMS["NMS (192.168.10.10)"]
        RGEST["R-GESTION (192.168.10.1)"]
        NMS ---|nms:eth1 <-> r-gestion:eth1| RGEST
    end

    subgraph Plano_Core["Plano Core L3"]
        R1["Router R1"]
        R2["Router R2"]
        RGEST ---|eth2 <-> eth1 (192.168.11.0/30)| R1
        RGEST ---|eth3 <-> eth1 (192.168.12.0/30)| R2
        R1 ===|r1:eth2 <-> r2:eth2 (10.0.0.0/30 Troncal OSPF)|=== R2
    end

    subgraph Plano_Acceso["Plano de Acceso y Clientes"]
        RACC["R-ACCESO"]
        PC1["PC1 Cliente (192.168.20.50)"]
        R1 ---|r1:eth3 <-> r-acceso:eth1 (192.168.21.0/30 Primario)| RACC
        R2 -.-|r2:eth3 <-> r-acceso:eth2 (192.168.22.0/30 Respaldo)|-.- RACC
        RACC ---|r-acceso:eth3 <-> pc1:eth1 (192.168.20.0/24 LAN)| PC1
    end
```

---

## 2. Matriz Resumen de Auto-Recuperación (Self-Healing)

| Dispositivo | Interfaz | Rol de la Interfaz | ¿Auto-Recuperación? | Tiempo Estimado | ¿Afecta Tráfico PC1? |
| :--- | :--- | :--- | :---: | :---: | :---: |
| **`r1`** | **`eth1`** | Gestión OOB (hacia R-GESTION) | ❌ **No** | Requiere manual | ⚠️ Sí (NMS pierde ping a PC1) |
| **`r1`** | **`eth2`** | Troncal Core P2P (hacia R2) |  **Sí** | 2 a 4 seg | ❌ No |
| **`r1`** | **`eth3`** | Enlace Primario L3 (hacia R-ACCESO) |  **Sí** | 2 a 5 seg | ❌ No (Conmuta a R2 en <1s) |
| **`r2`** | **`eth1`** | Gestión OOB (hacia R-GESTION) | ❌ **No** | Requiere manual | ❌ No |
| **`r2`** | **`eth2`** | Troncal Core P2P (hacia R1) |  **Sí** | 2 a 4 seg | ❌ No |
| **`r2`** | **`eth3`** | Enlace Respaldo L3 (hacia R-ACCESO) |  **Sí** | 2 a 4 seg | ❌ No |
| **`r-acceso`** | **`eth1`** | Enlace Primario L3 (hacia R1) |  **Sí** | 2 a 4 seg | ❌ No (Conmuta a R2 en <1s) |
| **`r-acceso`** | **`eth2`** | Enlace Respaldo L3 (hacia R2) |  **Sí** | 2 a 4 seg | ❌ No |
| **`r-acceso`** | **`eth3`** | Gateway LAN (hacia PC1) |  **Sí** | 2 a 4 seg | ⚠️ Sí (2-4s mientras repara) |
| **`r-gestion`** | **`eth1` / `eth2` / `eth3`** | Conexiones de Control OOB | ❌ **No** | Requiere manual | ❌ No en PC1 (Aísla NMS) |
| **`pc1`** | **`eth1`** | Tarjeta de Red del Host Cliente | ❌ **No** | Requiere manual | 🚨 Sí (PC1 sin red) |

---

## 3. Análisis Detallado por Interfaz y Casos de Prueba

### A. Router R1

#### 1. `r1:eth1` — Enlace de Gestión OOB (192.168.11.2)
* **Comando para apagar:** `docker exec r1 ip link set eth1 down`
* **¿Qué sucede?**
  - **Aislamiento del Plano de Gestión:** Se corta el canal físico por donde el NMS se comunica con R1 (SNMP y HTTP puerto 5000).
  - **Auto-recuperación:** **No se recupera sola** porque el NMS no puede llegar a R1 para ordenarle levantar la interfaz (*pérdida de la vía de control*).
  - **Efecto colateral:** En `r-gestion`, la ruta estática hacia `192.168.20.0/24` (PC1) pasaba por esta interfaz, por lo que el NMS emite alarma de `PC1 Cliente sin respuesta ICMP`.
* **Cómo recuperar:**
  ```bash
  docker exec r1 ip link set eth1 up
  ```

#### 2. `r1:eth2` — Troncal Core P2P (10.0.0.1)
* **Comando para apagar:** `docker exec r1 ip link set eth2 down`
* **¿Qué sucede?**
  - Cae la adyacencia OSPF directa entre R1 y R2.
  - El NMS lo detecta vía SNMP en R1 a través de `eth1` (que sigue sana).
  - El NMS llama a `http://192.168.11.2:5000/remediate` ordenando `restart_interface eth2`.
  - **La interfaz se reactiva sola en ~2 a 4 segundos.**
  - Grafana registra el evento en verde, sube el contador de *Auto-Heal Success* y calcula el MTTR.
  - El tráfico de PC1 no sufre ninguna interrupción.

#### 3. `r1:eth3` — Enlace Primario de Acceso hacia R-ACCESO (192.168.21.1)
* **Comando para apagar:** `docker exec r1 ip link set eth3 down`
* **¿Qué sucede?** *(El caso estrella de Alta Disponibilidad)*
  1. **Failover L3 inmediato:** El script `sla_tracker.sh` en `r-acceso` detecta la caída de pings a R1 en <1s.
  2. Retira la ruta por defecto por R1 (`192.168.21.1`) y entra la ruta flotante por R2 (`via 192.168.22.1 metric 10`).
  3. **PC1 no pierde conexión a Internet.**
  4. En Grafana, el panel **Active Path** cambia a `R2 (Backup Path)`.
  5. **Auto-Recuperación:** El NMS detecta `eth3` caída en R1, invoca el agente y la levanta sola.
  6. **Preemption:** Al revivir la interfaz, `sla_tracker.sh` detecta a R1 de regreso y restaura la ruta primaria de forma limpia.

---

### B. Router R2

#### 1. `r2:eth1` — Enlace de Gestión OOB (192.168.12.2)
* **Comando para apagar:** `docker exec r2 ip link set eth1 down`
* **¿Qué sucede?**
  - R2 queda aislado del monitoreo del NMS.
  - **No se recupera sola.**
  - PC1 sigue navegando con normalidad por R1.
* **Cómo recuperar:** `docker exec r2 ip link set eth1 up`

#### 2. `r2:eth2` — Troncal Core P2P (10.0.0.2)
* **Comando para apagar:** `docker exec r2 ip link set eth2 down`
* **¿Qué sucede?**
  - Mismo comportamiento que `r1:eth2`: **Se recupera sola en 2–4 segundos** por acción del NMS.

#### 3. `r2:eth3` — Enlace de Respaldo hacia R-ACCESO (192.168.22.1)
* **Comando para apagar:** `docker exec r2 ip link set eth3 down`
* **¿Qué sucede?**
  - Cae el camino de contingencia hacia R-ACCESO.
  - Mientras R1 esté sano, el tráfico de PC1 no se entera.
  - **El NMS detecta la caída en R2 y la recupera sola en 2–4 segundos.**

---

### C. Router R-ACCESO

#### 1. `r-acceso:eth1` — Extremo Acceso hacia R1 (192.168.21.2)
* **Comando para apagar:** `docker exec r-acceso ip link set eth1 down`
* **¿Qué sucede?**
  - Activa la conmutación inmediata de tráfico hacia R2.
  - **El NMS la repara solo:** El NMS accede a R-ACCESO a través de la IP de respaldo (`192.168.22.2`), envía la remediación y levanta `eth1`.

#### 2. `r-acceso:eth2` — Extremo Acceso hacia R2 (192.168.22.2)
* **Comando para apagar:** `docker exec r-acceso ip link set eth2 down`
* **¿Qué sucede?**
  - Se pierde la contingencia a R2 temporalmente.
  - El NMS la detecta y **la repara solo en 2–4 segundos** a través de la IP primaria (`192.168.21.2`).

#### 3. `r-acceso:eth3` — Gateway hacia PC1 (192.168.20.1)
* **Comando para apagar:** `docker exec r-acceso ip link set eth3 down`
* **¿Qué sucede?**
  - PC1 pierde temporalmente su puerta de enlace local.
  - El NMS detecta `PC1 unreachable` y `r-acceso:eth3 DOWN`.
  - **El NMS envía la orden de auto-remediación a R-ACCESO.**
  - `eth3` se levanta automáticamente en ~3 segundos.
  - PC1 recupera la conectividad y Grafana registra el MTTR de recuperación del cliente.

---

### D. Host PC1

#### 1. `pc1:eth1` — Interfaz LAN Cliente (192.168.20.50)
* **Comando para apagar:** `docker exec pc1 ip link set eth1 down`
* **¿Qué sucede?**
  - PC1 queda totalmente desconectado.
  - **No se auto-repara:** Al ser un host cliente final (Alpine Linux), no cuenta con demonio NetDevOps de remediación.
  - Grafana dispara alarma roja crítica: `PC1 Cliente Inaccesible`.
* **Cómo recuperar:**
  ```bash
  docker exec pc1 ip link set eth1 up
  ```

---

## 4. Guía Rápida de Monitoreo en Vivo

Para observar la auto-recuperación en tiempo real durante tus pruebas:

1. **Terminal con la bitácora del NMS:**
   ```bash
   docker exec -it nms tail -f /app/incidentes_red.log
   ```
2. **Terminal con tráfico ICMP continuo desde PC1:**
   ```bash
   docker exec -it pc1 ping 8.8.8.8
   ```
3. **Dashboard Grafana:**
   - URL: `http://localhost:3000` (Login: `admin` / `admin`)
   - Panel clave: **FAILOVER & SELF-HEALING**, **Self-Healing Lifecycle** y **MTTR Gauge**.
