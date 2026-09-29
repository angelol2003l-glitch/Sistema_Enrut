#!/usr/bin/env python3
"""Genera configuraciones SNMP locales a partir del .env ignorado por Git."""
from pathlib import Path
import os
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tmp" / "runtime-config"
DEVICES = ("r-gestion", "r1", "r2", "r-acceso")


def read_env():
    source = ROOT / ".env"
    if not source.is_file():
        raise ValueError("Falta .env; copia .env.example y define valores locales")
    values = {}
    for line in source.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError("Formato invalido en .env")
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def write_secret(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    # Truncar el mismo inode conserva los bind mounts del laboratorio ya iniciado.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as output:
        output.write(contents)


def main():
    values = read_env()
    community = values.get("SNMP_COMMUNITY", "")
    password = values.get("GRAFANA_ADMIN_PASSWORD", "")
    if not re.fullmatch(r"[A-Za-z0-9_-]{12,64}", community) or community == "CHANGE_ME":
        raise ValueError("SNMP_COMMUNITY requiere 12-64 caracteres alfanumericos, _ o -")
    if len(password) < 12 or password == "CHANGE_ME":
        raise ValueError("Define GRAFANA_ADMIN_PASSWORD local de al menos 12 caracteres")
    OUT.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(OUT, 0o700)
    for device in DEVICES:
        template = ROOT / "configs" / device / "snmpd.conf.template"
        rendered = template.read_text(encoding="utf-8").replace("{{SNMP_COMMUNITY}}", community)
        write_secret(OUT / device / "snmpd.conf", rendered)
    template = ROOT / "monitoring" / "snmp_exporter" / "snmp.yml.template"
    rendered = template.read_text(encoding="utf-8").replace("{{SNMP_COMMUNITY}}", community)
    write_secret(OUT / "snmp.yml", rendered)
    write_secret(OUT / "snmp_community", community + "\n")
    os.chmod(ROOT / ".env", 0o600)
    print("Configuraciones SNMP locales generadas en tmp/runtime-config/")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
