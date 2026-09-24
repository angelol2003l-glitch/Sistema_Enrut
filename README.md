# Sistema de Enrutamiento L3 con Alta Disponibilidad y Telemetría NMS

Laboratorio de redes automatizado con Containerlab, FRRouting (FRR), failover autónomo en Capa 3 y monitoreo centralizado con SNMP y Python.

---

## 1. Requisitos del Sistema

Para ejecutar este proyecto en tu laptop necesitas:
* **Sistema Operativo**: Linux (Ubuntu 22.04 LTS o superior) o **Windows 10/11 con WSL2 (Ubuntu)**.
* **Docker Engine**: En ejecución.
* **Containerlab**: Instalado (`clab`).
* **Git**: Para clonar el repositorio.

---

## 2. Instalación de Herramientas (Si no las tienes instaladas)

Ejecuta estos comandos en tu terminal de Ubuntu / WSL2:

### A. Dependencias básicas
```bash
sudo apt update && sudo apt install -y curl git iproute2 iputils-ping
```

### B. Instalar Docker Engine (si aún no lo tienes)
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker
sudo systemctl enable --now docker
```
> **Nota para Windows**: Si usas Docker Desktop en Windows, asegúrate de activar la integración con tu distribución de WSL2 en **Settings > Resources > WSL Integration**.

### C. Instalar Containerlab
```bash
bash -c "$(curl -sL https://get.containerlab.dev)"
```
Comprueba la instalación:
```bash
containerlab version
```

---

## 3. Clonar el Repositorio

```bash
git clone https://github.com/angelol2003l-glitch/Sistema_Enrut.git
cd Sistema_Enrut
```

---

## 4. Construcción de Imágenes Docker

Antes de levantar el laboratorio por primera vez, construye las dos imágenes locales necesarias:

```bash
# 1. Imagen de routers (FRRouting + Net-SNMP)
docker build -t frr-snmp:latest -f configs/Dockerfile.frr-snmp configs/

# 2. Imagen de la estación NMS (Python 3.11 + herramientas de red)
docker build -t nms-telemetry:latest nms/
```

Verifica que las imágenes existan:
```bash
docker images | grep -E "frr-snmp|nms-telemetry"
```

---

## 5. Levantar el Laboratorio

Despliega toda la topología de red con un solo comando:

```bash
sudo clab deploy -t topology.clab.yml
```

Verifica que los 6 contenedores estén corriendo (`pc1`, `r-acceso`, `r1`, `r2`, `r-gestion`, `nms`):
```bash
docker ps
```

---

## 6. Comandos de Inspección con Containerlab (`sudo clab`)

Containerlab incluye comandos nativos muy útiles para auditar nodos, interfaces y rutas sin tener que entrar uno por uno:

### A. Inspeccionar el estado de los nodos del laboratorio
Muestra una tabla con nombres, imágenes, estado y direcciones IP de gestión:
```bash
sudo clab inspect -t topology.clab.yml
```
Para ver detalles avanzados (incluyendo interfaces y bridges del host):
```bash
sudo clab inspect -t topology.clab.yml --details
```

### B. Ver las interfaces y direcciones IP de TODOS los nodos
Ejecuta un comando en todos los contenedores al mismo tiempo:
```bash
# Ver interfaces en formato resumido en toda la red
sudo clab exec -t topology.clab.yml --cmd "ip -br addr"

# Ver enlaces físicos virtuales (veth)
sudo clab exec -t topology.clab.yml --cmd "ip -br link"
```

### C. Ver interfaces o rutas de un nodo específico con clab
```bash
# Ver interfaces solo en R-ACCESO
sudo clab exec -t topology.clab.yml --label clab-node-name=r-acceso --cmd "ip -br addr"

# Ver la tabla de rutas del kernel en R-ACCESO
sudo clab exec -t topology.clab.yml --label clab-node-name=r-acceso --cmd "ip route"

# Ver rutas en FRRouting (Zebra) dentro de R1
sudo clab exec -t topology.clab.yml --label clab-node-name=r1 --cmd "vtysh -c 'show ip route'"

# Ver estado de interfaces en FRR en R2
sudo clab exec -t topology.clab.yml --label clab-node-name=r2 --cmd "vtysh -c 'show interface brief'"
```

### D. Ver el grafo visual de la topología en el navegador
Containerlab levanta un servidor web local con el diagrama interactivo de la red:
```bash
sudo clab graph -t topology.clab.yml
```
*(Abre en tu navegador la URL que te indique la terminal, por ejemplo: `http://localhost:50080`)*

---

## 7. Iniciar el Monitoreo NMS

Inicia el servicio de telemetría dentro del contenedor `nms`:

```bash
# Ejecutar el monitor en segundo plano
docker exec -d nms python3 /app/monitor_definitivo.py

# Ver la bitácora de eventos en tiempo real
docker exec -it nms tail -f /app/incidentes_red.log
```

---

## 8. Comandos de Prueba y Validación

### A. Probar conmutación por falla (Failover automático)
Abre otra terminal y ejecuta el script automatizado:
```bash
bash scripts/test_failover.sh
```
*Este script simula la caída del enlace primario en R1 (`eth3`), valida que el tráfico de PC1 no se pierda pasando a R2 por la ruta flotante, restaura el enlace y muestra la bitácora forense del NMS.*

### B. Auditar SNMP en todos los routers
```bash
bash scripts/verify_snmp.sh
```

---

## 9. Comandos Útiles con Docker

### Entrar a la consola interactiva de un router (FRR / vtysh)
```bash
# Acceder a la CLI de R1
docker exec -it r1 vtysh

# Ver tabla de rutas
show ip route

# Ver interfaces
show interface brief

# Salir
exit
```

### Probar conectividad desde el cliente PC1
```bash
docker exec -it pc1 ping 8.8.8.8
```

---

## 10. Detener y Destruir el Laboratorio

Cuando termines tu sesión de trabajo, elimina la topología y limpia las interfaces virtuales:

```bash
sudo clab destroy -t topology.clab.yml --cleanup
```

---

## Historial de Construcción del Proyecto
Para conocer a detalle todos los pasos técnicos realizados para crear y configurar este proyecto desde cero, consulta el archivo:
📄 **`PASOS_REALIZADOS.md`**
