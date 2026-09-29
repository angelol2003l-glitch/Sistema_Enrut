# Monitoreo y alta disponibilidad de red

## 2. Descripción breve

Laboratorio de monitoreo y alta disponibilidad de red construido con Containerlab y FRRouting. Integra telemetría SNMP, Prometheus, Grafana, Alertmanager y automatización para observar el estado de los routers, conmutar hacia una ruta de respaldo y recuperar la ruta principal.

## 3. Objetivo

Demostrar en un entorno controlado cómo supervisar una topología enrutada, detectar una falla en el camino principal y mantener conectividad mediante un router de respaldo. El proyecto también registra eventos y presenta indicadores de disponibilidad y recuperación.

## 4. Arquitectura

El laboratorio tiene dos planos relacionados:

- **Plano de datos:** conecta los routers y el cliente, y proporciona una ruta principal y otra de respaldo.
- **Plano de monitoreo y automatización:** el NMS consulta los dispositivos por SNMP y ejecuta procesos de monitoreo y recuperación. Prometheus recopila métricas; Grafana las presenta y Alertmanager recibe las alertas configuradas.

El recorrido de red se resume así:

**NMS → R-GESTION → R1/R2 → R-ACCESO → PC1**

R-GESTION forma parte del plano de gestión. R1 es el router principal y R2 es el respaldo; ambos están interconectados y tienen conexión hacia R-GESTION y R-ACCESO. R-ACCESO actúa como gateway del cliente PC1. El NMS realiza el monitoreo y aloja procesos de automatización y registro de incidentes.

## 5. Tecnologías utilizadas

| Tecnología | Función en el proyecto |
|---|---|
| Containerlab | Define y despliega los nodos y enlaces del laboratorio. |
| FRRouting | Proporciona el enrutamiento L3 en los routers virtuales. |
| SNMP | Expone información de estado e interfaces de los dispositivos. |
| Prometheus | Recopila y almacena métricas, y evalúa reglas de alerta. |
| Grafana | Presenta métricas, estado, rutas y eventos en el dashboard NOC. |
| Alertmanager | Recibe las alertas generadas por Prometheus. |
| SNMP Exporter | Consulta equipos SNMP y expone sus datos como métricas para Prometheus. |
| Python | Implementa el monitor NMS y el servicio de remediación. |
| Bash | Inicia servicios, ejecuta el seguimiento de SLA y prueba el failover. |
| Docker / Compose | Construye las imágenes del laboratorio y ejecuta la plataforma de monitoreo. |

## 6. Topología de red

La topología definida en **topology.clab.yml** incluye:

- **nms**: servidor de monitoreo y automatización.
- **r-gestion**: router del plano de gestión.
- **r1**: router principal.
- **r2**: router de respaldo.
- **r-acceso**: gateway de la red del cliente.
- **pc1**: cliente de prueba.

R1 y R2 cuentan con enlaces hacia R-GESTION y R-ACCESO, además de un enlace entre ambos. En operación normal, R-ACCESO utiliza la ruta a través de R1; cuando se detecta la falla del camino principal, el seguimiento de SLA cambia la ruta hacia R2.

## 7. Monitoreo

Los agentes SNMP de los routers proporcionan información de dispositivos e interfaces. SNMP Exporter convierte esas consultas en métricas que Prometheus recopila según **monitoring/prometheus/prometheus.yml**. El NMS ejecuta **nms/monitor_definitivo.py** y registra eventos en su bitácora.

Prometheus también carga las reglas de **monitoring/prometheus/alert_rules.yml** y envía las alertas configuradas a Alertmanager. Las definiciones de SNMP Exporter se encuentran en **monitoring/snmp_exporter/snmp.yml.template**; el archivo efectivo se genera localmente.

## 8. Alta disponibilidad y failover

R1 ofrece el camino principal entre la red de gestión y la red de acceso. R2 mantiene el camino de respaldo. **automation/sla_tracker.sh**, ejecutado en R-ACCESO por **scripts/start_services.sh**, comprueba la disponibilidad del siguiente salto principal y actualiza la ruta por defecto para usar R2 ante una falla; al recuperarse R1, restaura el camino principal.

La prueba automatizada disponible es **scripts/test_failover.sh**. Para los pasos de ejecución, consulta [Prueba de failover](#14-prueba-de-failover).

## 9. Auto-recuperación

Los procesos de remediación se implementan en **automation/remediation_server.py** y se ejecutan en R1, R2 y R-ACCESO. El servicio ofrece endpoints de salud y remediación para acciones de red configuradas. El NMS y el seguimiento de SLA complementan este flujo con detección y registro de incidentes.

La lógica de recuperación se mantiene en los scripts y servicios del proyecto; el dashboard presenta sus resultados y métricas.

## 10. Dashboard de Grafana

Compose publica Grafana en [http://localhost:3000](http://localhost:3000). El dashboard provisionado está definido en **monitoring/grafana/dashboards/noc_l3_ha.json**; las fuentes de datos y su provisión están en **monitoring/grafana/provisioning/**.

El archivo Compose obtiene las credenciales locales de `.env` y conserva acceso anónimo en modo Viewer. La [guía de credenciales](docs/credentials.md) explica cómo generarlas y rotarlas sin descoordinar agentes, exporter y NMS.

## 11. Estructura del repositorio

Árbol de los archivos fuente y configuración del proyecto. Se omiten **.git/**, el directorio generado **clab-enrut-ha/** y archivos de ejecución locales.

~~~text
.
├── automation/
│   ├── remediation_server.py
│   ├── sh_wrapper
│   └── sla_tracker.sh
├── configs/
│   ├── .dockerignore
│   ├── Dockerfile.frr-snmp
│   ├── vtysh_profile.sh
│   ├── r-acceso/
│   │   ├── daemons
│   │   ├── frr.conf
│   │   └── snmpd.conf.template
│   ├── r-gestion/
│   │   ├── daemons
│   │   ├── frr.conf
│   │   └── snmpd.conf.template
│   ├── r1/
│   │   ├── daemons
│   │   ├── frr.conf
│   │   └── snmpd.conf.template
│   └── r2/
│       ├── daemons
│       ├── frr.conf
│       └── snmpd.conf.template
├── docs/
│   ├── credentials.md
│   └── images/
│       ├── topology.png
│       ├── grafana-overview.png
│       ├── network-monitoring.png
│       └── failover-recovery.png
├── monitoring/
│   ├── alertmanager/
│   │   └── alertmanager.yml
│   ├── grafana/
│   │   ├── dashboards/
│   │   │   └── noc_l3_ha.json
│   │   └── provisioning/
│   │       ├── dashboards/dashboards.yml
│   │       └── datasources/
│   │           ├── alertmanager.yml
│   │           └── prometheus.yml
│   ├── prometheus/
│   │   ├── alert_rules.yml
│   │   └── prometheus.yml
│   └── snmp_exporter/
│       └── snmp.yml.template
├── nms/
│   ├── .dockerignore
│   ├── Dockerfile
│   ├── monitor_definitivo.py
│   └── reporte_sla.py
├── scripts/
│   ├── render_runtime_config.py
│   ├── setup_native_docker.sh
│   ├── start_services.sh
│   ├── test_failover.sh
│   ├── verify_alertmanager.sh
│   ├── verify_common.sh
│   ├── verify_grafana.sh
│   ├── verify_ha.sh
│   ├── verify_nms.sh
│   ├── verify_prometheus.sh
│   ├── verify_snmp.sh
│   └── verify_snmp_exporter.sh
├── .env.example
├── .gitignore
├── README.md
├── docker-compose.yml
├── topology.clab.yml
└── topology.clab.yml.annotations.json
~~~

**clab-enrut-ha/** es salida de ejecución de Containerlab, no código fuente. El archivo **topology.clab.yml.annotations.json** conserva anotaciones visuales del editor; la topología ejecutable es **topology.clab.yml**.

## 12. Despliegue

Desde la raíz del repositorio, construye las imágenes requeridas por los nodos:

~~~bash
install -m 600 .env.example .env
# Edita .env y sustituye CHANGE_ME por dos valores locales propios.
python3 scripts/render_runtime_config.py
docker build -t frr-snmp:latest -f configs/Dockerfile.frr-snmp configs/
docker build -t nms-telemetry:latest -f nms/Dockerfile nms/
~~~

Despliega primero Containerlab. Este paso crea la red externa **clab** que utiliza Compose:

~~~bash
sudo clab deploy -t topology.clab.yml
~~~

Inicia los servicios de monitoreo y luego los procesos dentro de los nodos:

~~~bash
docker compose up -d
bash scripts/start_services.sh
~~~

El script **setup_native_docker.sh** está disponible para preparar Docker nativo en entornos donde sea necesario.

## 13. Verificación

Comprueba el estado de Containerlab y los contenedores:

~~~bash
sudo clab inspect -t topology.clab.yml
docker compose ps
~~~

Verifica Prometheus, SNMP Exporter y las consultas SNMP con los scripts disponibles:

~~~bash
bash scripts/verify_prometheus.sh
bash scripts/verify_snmp_exporter.sh
bash scripts/verify_snmp.sh
bash scripts/verify_grafana.sh
bash scripts/verify_alertmanager.sh
bash scripts/verify_nms.sh
bash scripts/verify_ha.sh
~~~

También puedes revisar los servicios desde el navegador:

- Prometheus: [http://localhost:9090/targets](http://localhost:9090/targets). Confirma que los targets están activos.
- SNMP Exporter: [http://localhost:9116](http://localhost:9116).
- Alertmanager: [http://localhost:9093](http://localhost:9093).
- Grafana: [http://localhost:3000](http://localhost:3000). Abre el dashboard provisionado **Network Operations Center - Alta disponibilidad L3**.

## 14. Prueba de failover

Con el laboratorio desplegado y los servicios iniciados, ejecuta:

~~~bash
bash scripts/test_failover.sh
~~~

El script exige la secuencia **R1 principal → R2 respaldo activo → recuperación de R1** y comprueba conectividad desde PC1 en cada estado. Durante la falla controlada pausa únicamente el agente de remediación de R1 para evitar que repare el enlace antes de observar R2. Al finalizar, o ante un error o interrupción, restaura el enlace y reanuda el agente.

Cada ruta tiene un timeout de 30 segundos (`FAILOVER_TIMEOUT`) y cada estado del NMS uno de 60 segundos (`FAILOVER_TELEMETRY_TIMEOUT`). La falla se mantiene 15 segundos (`FAILOVER_HOLD_SECONDS`) para observar estabilidad. Los tres valores admiten de 1 a 120 segundos. El script devuelve un código distinto de cero si falta un estado o falla la conectividad.

La prueba utiliza `8.8.8.8` como destino ICMP, configurable con `FAILOVER_PROBE_IP`. Esta comprobación necesita conectividad hacia el destino elegido.

El NMS consulta el siguiente salto de R-ACCESO por la red de gestión, independiente del enlace principal. Durante la prueba, comprueba también que las métricas de ruta activa sigan la secuencia R1 → R2 → R1.

## 15. Evidencias

Capturas del laboratorio en ejecución. Los valores son los observados al capturar cada vista; pueden cambiar al repetir las pruebas.

![Topología de red en Grafana](docs/images/topology.png)

El panel de topología muestra los seis dispositivos y sus funciones, con R1 como principal y R2 como respaldo. Es una representación simplificada de la arquitectura.

![Vista general del dashboard NOC](docs/images/grafana-overview.png)

La vista general reúne el estado de los dispositivos, los indicadores, las interfaces, las rutas y el tráfico del laboratorio.

![Interfaces supervisadas mediante SNMP](docs/images/network-monitoring.png)

La tabla de Grafana muestra las interfaces y su estado operativo a partir de las métricas de SNMP recopiladas por Prometheus.

![Resultado de la prueba de failover y recuperación](docs/images/failover-recovery.png)

Registro de una ejecución real de `scripts/test_failover.sh`: observa R1, conmuta a R2, comprueba conectividad desde PC1 y confirma el retorno a R1. La captura presenta el resumen de las líneas de estado y los resultados de ping de esa ejecución.

## 16. Mejoras futuras

- Incorporar una guía breve de solución de problemas para despliegue y conectividad.
- Ampliar las pruebas automatizadas para validar recuperación de ruta y estado de los targets.
- Sustituir las credenciales de demostración por secretos y controles adecuados si el entorno se expone fuera del equipo local.
