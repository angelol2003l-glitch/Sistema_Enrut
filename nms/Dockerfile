FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    iputils-ping \
    iproute2 \
    traceroute \
    snmp \
    procps \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir pysnmp-lextudio requests

WORKDIR /app
CMD ["sleep", "infinity"]
