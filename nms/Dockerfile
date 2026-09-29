# Imagen base ligera con Python 3.11 para ejecutar herramientas/scripts del NMS.
FROM python:3.11-slim

# Instala utilidades de diagnostico de red y SNMP usadas para pruebas y monitoreo.
# Al final limpia la cache de apt para mantener la imagen mas pequena.
RUN apt-get update && apt-get install -y --no-install-recommends \
    iputils-ping \
    iproute2 \
    traceroute \
    snmp \
    procps \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Instala librerias Python para consultas SNMP y llamadas HTTP/API.
RUN pip install --no-cache-dir pysnmp-lextudio requests

# Define el directorio de trabajo donde se montan o ejecutan los scripts del NMS.
WORKDIR /app

# Mantiene el contenedor activo para poder entrar, ejecutar pruebas y lanzar scripts manualmente.
CMD ["sleep", "infinity"]
