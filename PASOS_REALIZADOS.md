# Pasos Realizados para la Construcción del Proyecto

Este documento describe cronológicamente la metodología, decisiones técnicas y pasos que se ejecutaron para construir este laboratorio de enrutamiento con alta disponibilidad, failover autónomo y telemetría en **Containerlab**.

---

## Índice de Fases
1. [Fase 1: Diseño de la Arquitectura y Planos de Red](#fase-1-diseño-de-la-arquitectura-y-planos-de-red)
2. [Fase 2: Creación de las Imágenes Docker Personalizadas](#fase-2-creación-de-las-imágenes-docker-personalizadas)
3. [Fase 3: Construcción del Manifiesto de Topología (`topology.clab.yml`)](#fase-3-construcción-del-manifiesto-de-topología-topologyclabyml)
4. [Fase 4: Configuración de FRRouting (FRR)](#fase-4-configuración-de-frrouting-frr)
5. [Fase 5: Desarrollo del Mecanismo de Failover Autónomo (IP SLA / Tracking)](#fase-5-desarrollo-del-mecanismo-de-failover-autónomo-ip-sla--tracking)
6. [Fase 6: Implementación del Agente SNMPv2c](#fase-6-implementación-del-agente-snmpv2c)
7. [Fase 7: Desarrollo del Motor de Telemetría NMS en Python](#fase-7-desarrollo-del-motor-de-telemetría-nms-en-python)
8. [Fase 8: Creación de Scripts de Validación y Pruebas](#fase-8-creación-de-scripts-de-validación-y-pruebas)
9. [Fase 9: Preparación para Distribución y Despliegue en Otros Equipos](#fase-9-preparación-para-distribución-y-despliegue-en-otros-equipos)

---

## Fase 1: Diseño de la Arquitectura y Planos de Red

El proyecto nació con el objetivo de migrar una topología originalmente concebida en **GNS3 con routers Cisco 7200** hacia un modelo moderno de **Infraestructura como Código (IaC)** basado en contenedores.

### 1.1 Segmentación en Tres Planos Operativos
* **Plano de Gestión Fuera de Banda (OOB - Out of Band)**:
  * Subred `192.168.10.0/24` para la estación NMS.
  * Router dedicado `R-GESTION` que aísla el tráfico de monitoreo y telemetría del tráfico de producción.
* **Plano Core y Servicios P2P**:
  * Dos routers de tránsito: `R1` (Primario) y `R2` (Respaldo).
  * Ambos anuncian una IP de servicio simulada en Loopback: `8.8.8.8/32`.
  * Enlace troncal directo punto a punto entre ellos: `10.0.0.0/30`.
* **Plano de Acceso y Datos**:
  * Router `R-ACCESO`: Gateway de la red de clientes (`192.168.20.1/24`).
  * Conexión dual: enlace primario hacia R1 (`192.168.21.0/30`) y enlace de respaldo hacia R2 (`192.168.22.0/30`).
  * Host cliente emulado: `PC1` (`192.168.20.50/24`).

---

## Fase 2: Creación de las Imágenes Docker Personalizadas

Para evitar depender de software propietario, se crearon dos `Dockerfile`:

### 2.1 Imagen para los Routers (`configs/Dockerfile.frr-snmp`)
* **Base**: `frrouting/frr:latest` (Alpine Linux con suite FRR instalada).
* **Paquetes agregados**:
  * `net-snmp`: Para ejecutar el servicio de agente SNMP (`snmpd`).
  * `net-snmp-tools`: Herramientas de consulta (`snmpget`, `snmpwalk`).
  * `iputils`: Comandos de red avanzados (`ping`, `arping`).
* **Comando de construcción**:
  ```bash
  docker build -t frr-snmp:latest -f configs/Dockerfile.frr-snmp configs/
  ```

### 2.2 Imagen para la Estación NMS (`nms/Dockerfile`)
* **Base**: `python:3.11-slim`.
* **Paquetes de sistema**: `iputils-ping`, `iproute2`, `traceroute`, `snmp`, `procps`, `curl`.
* **Librerías Python**: `pysnmp-lextudio` y `requests`.
* **Comando de construcción**:
  ```bash
  docker build -t nms-telemetry:latest nms/
  ```

---

## Fase 3: Construcción del Manifiesto de Topología (`topology.clab.yml`)

Se redactó el archivo YAML maestro que le indica a Containerlab cómo desplegar toda la infraestructura:

1. **Configuración Global**:
   * `name: enrut-ha`: Nombre del laboratorio.
   * `prefix: ""`: Permite que los contenedores tengan nombres limpios (`r1`, `r-acceso`, `nms`) sin prefijos redundantes.
2. **Definición de Nodos (`nodes`)**:
   * Para cada nodo se especificó su imagen, tipo (`kind: linux`), montajes de volúmenes (`binds`) y comandos iniciales (`exec`).
   * En `exec` se configuró el reenvío de paquetes (`sysctl -w net.ipv4.ip_forward=1`), el inicio del agente SNMP (`snmpd`) y las rutas de gestión.
3. **Definición de Enlaces (`links`)**:
   * Se declararon los pares virtuales (`veth pairs`) conectando punto a punto las interfaces virtuales de cada contenedor.

---

## Fase 4: Configuración de FRRouting (FRR)

Para cada router en `configs/<router>/` se prepararon los archivos de configuración:

### 4.1 Archivo `daemons`
Se habilitaron únicamente los módulos necesarios para optimizar recursos:
```text
zebra=yes     # Daemon de comunicación con el kernel de Linux
staticd=yes   # Daemon para manejo de rutas estáticas
bfdd=yes      # Detección de reenvío bidireccional
```
Los protocolos dinámicos (OSPF, BGP, RIP) se mantuvieron apagados (`no`) al resolverse la arquitectura mediante rutas estáticas con métricas y script de tracking.

### 4.2 Archivo `frr.conf`
* **R-ACCESO**:
  * Configuración de interfaces `eth1` (hacia R1), `eth2` (hacia R2) y `eth3` (hacia clientes).
  * Ruta por defecto primaria: `ip route 0.0.0.0/0 192.168.21.1 1` (métrica 1).
  * Ruta por defecto flotante: `ip route 0.0.0.0/0 192.168.22.1 10` (métrica 10).
* **R1 y R2**:
  * Configuración de la Loopback virtual: `lo: 8.8.8.8/32`.
  * Troncal punto a punto en `eth2`: `10.0.0.0/30`.
  * Rutas de retorno hacia la red de clientes `192.168.20.0/24`.
* **R-GESTION**:
  * Rutas OOB hacia los routers y hacia el segmento del cliente vía R1 y R2.

---

## Fase 5: Desarrollo del Mecanismo de Failover Autónomo (IP SLA / Tracking)

En Cisco IOS, la conmutación automática ante caída de enlace se hace mediante `ip sla` + `track` + `ip route ... track 1`. Para lograr exactamente el mismo comportamiento en Linux y FRR, se programó el script `configs/r-acceso/sla_tracker.sh`:

1. **Monitoreo Continuo**: Envía una sonda ICMP (`ping -c 1 -W 1 -I eth1 192.168.21.1`) cada 2 segundos a través de la interfaz primaria.
2. **Detección de Falla con Histéresis**: Si el ping falla, realiza una segunda comprobación tras 1 segundo para evitar falsos positivos por fluctuaciones momentáneas.
3. **Conmutación**: Si se confirma la caída de R1:
   * Ejecuta: `ip route del default via 192.168.21.1 dev eth1`.
   * El kernel de Linux activa instantáneamente la ruta flotante de respaldo vía R2 (`192.168.22.1 metric 10`).
   * Escribe la alerta en `/var/log/sla_tracker.log`.
4. **Preemption (Restauración Automática)**: Cuando R1 vuelve a responder, reinyecta la ruta primaria con métrica 1 y conmuta el tráfico de regreso a R1.

---

## Fase 6: Implementación del Agente SNMPv2c

Para habilitar la observabilidad centralizada, se configuró `snmpd.conf` en todos los routers:
```text
rocommunity redes2026
syslocation Lab Containerlab
syscontact admin@redes.local
agentaddress udp:161
```
* **Comunidad**: `redes2026` con permisos de solo lectura (`RO`).
* **OIDs MIB-II expuestas**:
  * `1.3.6.1.2.1.1.5.0` (`sysName`): Identificación del router.
  * `1.3.6.1.2.1.2.2.1.2` (`ifDescr`): Nombre de las interfaces (`eth1`, `eth2`, etc.).
  * `1.3.6.1.2.1.2.2.1.8` (`ifOperStatus`): Estado operacional (1 = UP, 2 = DOWN).
  * `1.3.6.1.2.1.4.21.1.7.0.0.0.0` (`ipRouteNextHop`): Próximo salto activo en R-ACCESO (`.21.1` vs `.22.1`).

---

## Fase 7: Desarrollo del Motor de Telemetría NMS en Python

En `nms/monitor_definitivo.py` se construyó el demonio de telemetría:

1. **Auditoría de Cliente**: Verifica que `PC1` (`192.168.20.50`) responda a pings ICMP cada 2 segundos.
2. **Auditoría Multi-Hop con Fallback**:
   * Para consultar el próximo salto de `R-ACCESO`, primero intenta por `192.168.21.2` (camino vía R1).
   * Si el enlace de R1 cae, el socket conmuta automáticamente a `192.168.22.2` (camino vía R2), garantizando que el NMS nunca pierda la visibilidad de `R-ACCESO`.
3. **Detección por Flancos (Edge-Triggered)**:
   * Solo registra mensajes cuando ocurre un cambio de estado para no saturar los logs.
4. **Bitácora Forense**:
   * Escribe cada incidente con formato estandarizado en `/app/incidentes_red.log` (`[INFO]`, `[CRITICO]`, `[FAILOVER]`, `[RECUPERADO]`).

---

## Fase 8: Creación de Scripts de Validación y Pruebas

Para comprobar el correcto funcionamiento y facilitar demostraciones, se crearon dos scripts en `scripts/`:

### 8.1 `scripts/test_failover.sh`
* Comprueba conectividad nominal desde PC1 a 8.8.8.8.
* Desactiva la interfaz de R1 conectada a R-ACCESO (`docker exec r1 ip link set eth3 down`).
* Muestra cómo la ruta por defecto en R-ACCESO cambia a `192.168.22.1 metric 10`.
* Valida que PC1 siga teniendo salida con 0% pérdida de paquetes.
* Restaura la interfaz en R1 y muestra las últimas líneas del registro del NMS.

### 8.2 `scripts/verify_snmp.sh`
* Consulta las OIDs de nombre y estado de rutas en todos los routers directamente desde el NMS mediante `snmpget`.

---

## Fase 9: Preparación para Distribución y Despliegue en Otros Equipos

1. **Configuración de `.gitignore`**:
   * Se excluyó la carpeta de tiempo de ejecución `clab-enrut-ha/` y archivos `.log` volátiles.
2. **Permisos de Ejecución**:
   * Se asignaron permisos `chmod +x` a todos los scripts (`.sh`).
3. **Documentación de Usuario (`README.md`)**:
   * Se incluyó la guía rápida con comandos listos para copiar y pegar, facilitando que cualquier persona con Docker y Containerlab pueda clonar y desplegar el proyecto en su propia laptop en pocos minutos.


---

## Fase 10: Resolución de Conflictos en WSL2 (Docker Desktop vs Docker Engine Nativo)

### 10.1 Diagnóstico del Problema de Red en WSL2
Al desplegar Containerlab en entornos Windows con WSL2 donde coexiste **Docker Desktop**, se identificó el siguiente fallo:
* **Error**: `Failed to lookup link "br-xxxx": Link not found` y `Unable to determine NetNS Path`.
* **Causa Raíz**: Docker Desktop inyecta un proceso proxy (`docker-desktop-user-distro`) que monta un socket tmpfs sobre `/var/run/docker.sock`. Cuando Containerlab intenta crear la red de gestión (`clab`), el daemon de Docker Desktop crea los puentes de red dentro de la máquina virtual de utilidad de Docker (`docker-desktop`) y no en el espacio de nombres de red de la distribución de Ubuntu. En consecuencia, Containerlab no puede encontrar los puentes vía Netlink ni inyectar los enlaces virtuales `veth` en los contenedores.

### 10.2 Solución Implementada: Socket Dedicado para Docker Engine Nativo
Se automatizó la resolución en el script `scripts/setup_native_docker.sh`:
1. **Configuración de Systemd**: Se añadió un override en `/etc/systemd/system/docker.service.d/override.conf` para que el servicio nativo `dockerd` de Ubuntu escuche en `/run/docker-native.sock` y en `tcp://127.0.0.1:2375`.
2. **Preservación de Entorno**: Se configuró la variable `DOCKER_HOST=unix:///run/docker-native.sock` en `/etc/environment`, `/etc/profile.d/docker_native.sh` y en los archivos `~/.bashrc`.
3. **Persistencia con Sudo**: Se configuró `/etc/sudoers.d/docker_host` con `Defaults env_keep += "DOCKER_HOST"`, permitiendo que `sudo clab` herede automáticamente el socket nativo sin requerir parámetros adicionales.
4. **Contexto Docker**: Se creó y activó el contexto `native` apuntando al socket dedicado.

### 10.3 Automatización del Despliegue Limpio y Servicios
* Se creó el script `scripts/start_services.sh` para iniciar de manera idempotente los agentes de telemetría y tracking (`monitor_definitivo.py`, `sla_tracker.sh`).
* Se optimizó `topology.clab.yml` asignando `ip addr replace` previo a la inyección de rutas en R2 para evitar condiciones de carrera en el arranque de Zebra.
* Se estandarizó el comando de despliegue y reinicio:
  ```bash
  sudo clab deploy -t topology.clab.yml --reconfigure
  bash scripts/start_services.sh
  ```
