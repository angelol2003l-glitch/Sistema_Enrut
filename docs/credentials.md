# Credenciales locales del laboratorio

El repositorio conserva plantillas sin secretos. Las credenciales activas se definen en `.env` local, ignorado por Git. `scripts/render_runtime_config.py` genera en `tmp/runtime-config/` las configuraciones para los cuatro agentes SNMP, SNMP Exporter y el archivo que lee el NMS. Ese directorio tambien esta ignorado y restringido al propietario.

## Preparacion

1. Ejecuta `install -m 600 .env.example .env` y define `GRAFANA_ADMIN_PASSWORD` y `SNMP_COMMUNITY` con valores propios. La comunidad admite de 12 a 64 letras, numeros, `_` o `-`; la contrasena requiere al menos 12 caracteres. No uses `CHANGE_ME`.
2. Ejecuta `python3 scripts/render_runtime_config.py` antes de desplegar Containerlab o Compose. El renderizador limita los permisos de `.env` y de los archivos generados a `0600`.
3. Sigue el orden de despliegue del README. Prometheus usa el perfil fijo `lab_snmp`, cuyo valor efectivo esta en la configuracion local del exporter. Los verificadores no contienen la comunidad.

Las variables `GRAFANA_ADMIN_USER` y `GRAFANA_ADMIN_PASSWORD` se interpolan desde `.env` en Compose. La contrasena de Grafana en un volumen ya existente no cambia al editar `.env`; hay que rotarla tambien en Grafana. Para la cuenta `admin` del laboratorio, se puede ejecutar `grafana cli admin reset-admin-password` dentro del contenedor pasando la nueva contrasena por un mecanismo local que no la imprima en consola ni en historial de shell.

## Rotacion

Actualiza `.env`, ejecuta el renderizador y recrea el laboratorio con `sudo clab deploy -t topology.clab.yml --reconfigure`. Recrea los servicios con `docker compose up -d`, recarga Prometheus con `curl -fsS -X POST http://localhost:9090/-/reload` y vuelve a ejecutar los siete verificadores. La comunidad SNMPv2c viaja sin cifrar por la red del laboratorio; no debe reutilizarse fuera de el.

Los valores de demostracion anteriores permanecen en commits previos. Se sustituyeron en el arbol actual y se rotaron localmente, pero una limpieza del historial requeriria un cambio deliberado de los identificadores de commits.
