#!/bin/bash
# ─── setup-etapa1.sh ──────────────────────────────────────────────────────────
# Configura SFTPGo per a l'Etapa 1: FTP sense xifrat
# S'executa dins del contenidor server
set -e

echo "=== Etapa 1: Configuració SFTPGo FTP sense xifrat ==="

# Copiar la configuració de l'etapa 1
cp /etc/sftpgo/etapa1/sftpgo.json /etc/sftpgo/sftpgo.json
chown sftpgo:sftpgo /etc/sftpgo/sftpgo.json

# Inicialitzar la base de dades si no existeix
if [ ! -f /var/lib/sftpgo/sftpgo.db ]; then
    echo "[etapa1] Inicialitzant base de dades SFTPGo..."
    sftpgo initprovider --config-file /etc/sftpgo/etapa1/sftpgo.json
fi

# Crear l'usuari administrador (si no existeix)
echo "[etapa1] Creant usuari admin..."
sftpgo resetprovider --config-file /etc/sftpgo/etapa1/sftpgo.json || true

# Crear directori per a l'usuari FTP
mkdir -p /srv/sftpgo/data/ftpuser
chown -R sftpgo:sftpgo /srv/sftpgo/data

echo "[etapa1] Configuració completada."
echo ""
echo "  URL Admin: http://demoftp.test:8080/web/admin"
echo "  Host FTP:  demoftp.test"
echo "  Port FTP:  21"
echo "  Mode:      FTP (SENSE XIFRAT - per a pràctica)"
echo ""
echo "  Credencials SFTPGo admin: admin / admin"
echo "  (Canvia-les en el primer accés)"
echo ""
