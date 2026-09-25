# Sistema de Enrutamiento L3 con Alta Disponibilidad y Telemetría NMS

Laboratorio de redes automatizado con **Containerlab**, **FRRouting (FRR)**, conmutación por falla autónoma en Capa 3 (Failover / IP SLA tracking) y monitoreo centralizado con SNMP y Python.

---

## 1. Requisitos del Sistema

Para ejecutar este proyecto en tu laptop necesitas:
* **Sistema Operativo**: Linux (Ubuntu 22.04 LTS o superior) o **Windows 10/11 con WSL2 (Ubuntu)**.
* **Docker Engine**: Instalado y en ejecución (se recomienda Docker Engine nativo en Linux/WSL2).
* **Containerlab**: Instalado (`clab`).
* **Git**: Para clonar el repositorio.

---

## 2. Instalación de Herramientas (Si no las tienes instaladas)

Ejecuta estos comandos en tu terminal de Ubuntu / WSL2:

### A. Dependencias básicas
```bash
sudo apt update && sudo apt install -y curl git iproute2 iputils-ping
```

### B. Instalar Docker Engine Nativo
Containerlab requiere manipular directamente puentes del kernel Linux (`br-xxxx`), enlaces virtuales (`veth`) y namespaces de red:
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
sudo systemctl enable --now docker
```

> **IMPORTANTE (Usuarios de Windows con WSL2 + Docker Desktop)**:
> Si tienes Docker Desktop instalado en Windows, este puede secuestrar el socket `/var/run/docker.sock`, provocando el error `Failed to lookup link: Link not found`.
> Para solucionar esto de forma automática y definitiva en tu terminal de WSL2, ejecuta una única vez:
> ```bash
> sudo bash scripts/setup_native_docker.sh
> ```
> *(Este script configura un socket dedicado para el daemon nativo y asegura que Containerlab funcione sin interferencias).*

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

### A. Desplegar la topología de red
Despliega todos los enrutadores, la estación NMS y el host cliente:

```bash
sudo clab deploy -t topology.clab.yml
```
*(Si ya tenías una sesión previa o deseas recrear los enlaces limpios desde cero, utiliza el flag `--reconfigure`: `sudo clab deploy -t topology.clab.yml --reconfigure`)*

### B. Iniciar los servicios de telemetría y tracking
Inicia el motor de telemetría en el NMS y el rastreador de SLA en R-ACCESO con el script automatizado:
```bash
bash scripts/start_services.sh
```

### C. Verificar que los 6 nodos estén corriendo
```bash
docker ps
```
Deberás ver los contenedores: `pc1`, `r-acceso`, `r1`, `r2`, `r-gestion` y `nms`.

---

## 6. Comandos de Inspección con Containerlab (`sudo clab`)

Containerlab incluye comandos nativos para auditar nodos, interfaces y rutas sin tener que entrar uno por uno:

### A. Inspeccionar el estado de los nodos del laboratorio
Muestra una tabla con nombres, imágenes, estado y direcciones IP de gestión:
```bash
sudo clab inspect -t topology.clab.yml
```

### B. Ver las interfaces y direcciones IP de TODOS los nodos
```bash
# Ver interfaces en formato resumido en toda la red
sudo clab exec -t topology.clab.yml --cmd "ip -br addr"

# Ver enlaces físicos virtuales (veth)
sudo clab exec -t topology.clab.yml --cmd "ip -br link"
```

### C. Ver interfaces o rutas de un nodo específico
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

### D. Ver el grafo visual interactivo en el navegador
Containerlab levanta un servidor web con el diagrama interactivo de la topología:
```bash
sudo clab graph -t topology.clab.yml --srv 0.0.0.0:50080
```
Abre en tu navegador:
👉 **[http://localhost:50080](http://localhost:50080)**

---

## 7. Monitoreo y Bitácora Forense NMS

### A. Ver la bitácora de eventos en tiempo real
Visualiza en vivo los eventos de conectividad, caídas de enlaces y conmutaciones:
```bash
docker exec -it nms tail -f /app/incidentes_red.log
```

### B. Generar el reporte de SLA y métricas de MTTR
Ejecuta el script analítico para calcular disponibilidad y tiempo medio de recuperación:
```bash
python3 nms/reporte_sla.py
```

---

## 8. Comandos de Prueba y Validación

### A. Probar conmutación por falla (Failover automático)
Ejecuta el script de prueba automatizado:
```bash
bash scripts/test_failover.sh
```
*Este script simula la caída del enlace primario en R1 (`eth3`), valida que el tráfico de PC1 no se pierda pasando a R2 por la ruta flotante (0% pérdida de paquetes), restaura el enlace y muestra la bitácora forense del NMS.*

### B. Auditar SNMP en todos los routers
```bash
bash scripts/verify_snmp.sh
```

---

## 9. Comandos Útiles de Operación

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

## 10. Solución de Problemas (Troubleshooting WSL2 & Docker)

### Problema: `Failed to lookup link "br-xxxx": Link not found` o `namespace path not available`
* **Causa**: Ocurre en Windows con WSL2 cuando **Docker Desktop** intercepta las llamadas a la API de Docker mediante su proxy. Docker Desktop crea los puentes de red dentro de su propia máquina virtual de utilidad (`docker-desktop`), por lo que Containerlab (que corre en Ubuntu) no puede encontrar el dispositivo de red ni inyectar las interfaces en el kernel.
* **Solución**:
  Ejecuta el script de aprovisionamiento de Docker nativo:
  ```bash
  sudo bash scripts/setup_native_docker.sh
  ```
  Esto configura un socket directo con el motor nativo de Linux (`/run/docker-native.sock`) preservado en `DOCKER_HOST`.

### Cómo reiniciar o recrear el laboratorio completamente
Si por alguna razón necesitas resetear el laboratorio a un estado limpio:
```bash
# 1. Destruir y limpiar interfaces previas
sudo clab destroy -t topology.clab.yml --cleanup

# 2. Desplegar de nuevo la topología
sudo clab deploy -t topology.clab.yml --reconfigure

# 3. Iniciar servicios en segundo plano
bash scripts/start_services.sh
```

---

## 11. Detener y Destruir el Laboratorio

Cuando termines tu sesión de trabajo, elimina la topología y limpia las interfaces virtuales:

```bash
sudo clab destroy -t topology.clab.yml --cleanup
```

---

## Historial de Construcción del Proyecto
Para conocer a detalle todos los pasos técnicos realizados para crear y configurar este proyecto desde cero, consulta el archivo:
📄 **`PASOS_REALIZADOS.md`**
