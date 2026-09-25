#!/usr/bin/env bash
# Script de configuracion para resolver conflictos entre Docker Desktop WSL2 y Containerlab
# Asegura que Containerlab interactue con el Docker Engine nativo de Linux y sus interfaces de red
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Este script debe ejecutarse con privilegios de root (sudo bash scripts/setup_native_docker.sh)"
    exit 1
fi

echo "================================================================="
echo "   CONFIGURACION DOCKER NATIVO PARA CONTAINERLAB EN WSL2 / LINUX "
echo "================================================================="

TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"

# 1. Configurar override para systemd dockerd nativo
echo "[1/6] Configurando socket dedicado para dockerd (/run/docker-native.sock)..."
mkdir -p /etc/systemd/system/docker.service.d
cat << 'OVR' > /etc/systemd/system/docker.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H tcp://127.0.0.1:2375 -H unix:///run/docker-native.sock --containerd=/run/containerd/containerd.sock
OVR

systemctl daemon-reload
systemctl restart docker

# 2. Configurar DOCKER_HOST en /etc/environment
echo "[2/6] Configurando DOCKER_HOST en /etc/environment..."
if ! grep -q "DOCKER_HOST" /etc/environment 2>/dev/null; then
    echo "DOCKER_HOST=unix:///run/docker-native.sock" >> /etc/environment
fi

# 3. Configurar profile.d para shells interactivos
echo "[3/6] Registrando variable de entorno en /etc/profile.d/docker_native.sh..."
cat << 'PRF' > /etc/profile.d/docker_native.sh
export DOCKER_HOST=unix:///run/docker-native.sock
PRF
chmod +x /etc/profile.d/docker_native.sh

# 4. Configurar ~/.bashrc de root y del usuario local
echo "[4/6] Configurando ~/.bashrc..."
if ! grep -q "unix:///run/docker-native.sock" /root/.bashrc 2>/dev/null; then
    echo 'export DOCKER_HOST=unix:///run/docker-native.sock' >> /root/.bashrc
fi

if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ] && id "$TARGET_USER" >/dev/null 2>&1; then
    USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    if [ -f "$USER_HOME/.bashrc" ] && ! grep -q "unix:///run/docker-native.sock" "$USER_HOME/.bashrc" 2>/dev/null; then
        echo 'export DOCKER_HOST=unix:///run/docker-native.sock' >> "$USER_HOME/.bashrc"
    fi
fi

# 5. Configurar sudoers para preservar DOCKER_HOST
echo "[5/6] Configurando sudoers para preservar variable DOCKER_HOST..."
cat << 'SUD' > /etc/sudoers.d/docker_host
Defaults env_keep += "DOCKER_HOST"
SUD
chmod 0440 /etc/sudoers.d/docker_host
/usr/sbin/visudo -c -f /etc/sudoers.d/docker_host >/dev/null

# 6. Configurar docker context "native"
echo "[6/6] Configurando contexto de Docker 'native'..."
export DOCKER_HOST=unix:///run/docker-native.sock
docker context create native --docker host=unix:///run/docker-native.sock 2>/dev/null || docker context update native --docker host=unix:///run/docker-native.sock 2>/dev/null || true
docker context use native 2>/dev/null || true

if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ] && id "$TARGET_USER" >/dev/null 2>&1; then
    su - "$TARGET_USER" -c "export DOCKER_HOST=unix:///run/docker-native.sock && (docker context create native --docker host=unix:///run/docker-native.sock 2>/dev/null || docker context update native --docker host=unix:///run/docker-native.sock 2>/dev/null || true) && docker context use native 2>/dev/null || true" 2>/dev/null || true
fi

echo "================================================================="
echo "  ✓ CONFIGURACION COMPLETADA EXITOSAMENTE                         "
echo "  Containerlab ahora se comunicara directamente con el Docker nativo."
echo "================================================================="
