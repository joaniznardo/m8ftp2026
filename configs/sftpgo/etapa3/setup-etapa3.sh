#!/bin/bash
# ─── setup-etapa3.sh ──────────────────────────────────────────────────────────
# Configura SFTPGo per a l'Etapa 3: backend S3 amb MinIO/RustFS
# S'executa des del HOST despres de desplegar el lab: ./lab.sh setup 3
# Prerequisit: Etapa 2 completada (certificats mkcert existents)
set -e

LAB_NAME="sftpgo-lab"
SERVER="clab-${LAB_NAME}-server"
CLIENT="clab-${LAB_NAME}-client"
MINIO="clab-${LAB_NAME}-rustfs"

MINIO_IP="10.50.0.30"
MINIO_ENDPOINT="http://${MINIO_IP}:9000"
MINIO_ACCESS="rustfs-access-key"
MINIO_SECRET="rustfs-secret-key"
BUCKET="sftpgo-data"

echo "=== Etapa 3: Configuracio S3 (MinIO/RustFS) ==="
echo ""

# ─── 1. Verificar que el contenidor MinIO existeix ───────────────────────────
if ! docker ps --format '{{.Names}}' | grep -q "^${MINIO}$"; then
    echo "ERROR: El contenidor '${MINIO}' no s'ha trobat."
    echo "       Assegura't d'haver desplegat l'etapa 3: ./lab.sh deploy 3"
    exit 1
fi

echo "[etapa3] Contenidor MinIO: $MINIO trobat."

# ─── 2. Esperar que MinIO estigui disponible ─────────────────────────────────
# MinIO te curl. Fem health check des de dins del contenidor amb localhost.
echo "[etapa3] Esperant que MinIO estigui disponible..."
for i in $(seq 1 30); do
    if docker exec "$MINIO" curl -sf "http://localhost:9000/minio/health/live" &>/dev/null; then
        echo "[etapa3] MinIO disponible."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[etapa3] AVIS: MinIO no respon despres de 60s. Continuant igualment..."
    fi
    sleep 2
done

# ─── 3. Crear el bucket sftpgo-data via mc (dins del contenidor MinIO) ───────
# La imatge minio/minio te mc (MinIO Client) integrat.
echo "[etapa3] Configurant alias mc i creant bucket '${BUCKET}'..."
docker exec "$MINIO" mc alias set local \
    "http://localhost:9000" "$MINIO_ACCESS" "$MINIO_SECRET" --api S3v4 2>/dev/null || true

docker exec "$MINIO" mc mb "local/${BUCKET}" 2>/dev/null || \
    echo "[etapa3] El bucket ja existia."

docker exec "$MINIO" mc ls local/
echo "[etapa3] Bucket '${BUCKET}' creat."

# ─── 4. Instruccions per configurar l'usuari S3 ─────────────────────────────
# SFTPGo ja esta arrancant amb la configuracio correcta (etapa3/sftpgo.json
# bind-muntat a /etc/sftpgo/sftpgo.json). L'usuari ftpuser ja s'ha creat
# automaticament per server-init.sh amb filesystem local.
# Per usar S3, cal modificar l'usuari via l'admin web.
echo ""
echo "=== Configuracio completada ==="
echo ""
echo "  MinIO/RustFS esta disponible amb el bucket '${BUCKET}' creat."
echo ""
echo "  Per configurar l'usuari ftpuser amb backend S3:"
echo ""
echo "  1. Obre el panell d'admin SFTPGo: https://localhost:8081/web/admin"
echo "  2. Inicia sessio com admin/admin"
echo "  3. Users -> ftpuser -> Edit -> Filesystem -> S3 Compatible"
echo ""
echo "     Endpoint:   ${MINIO_ENDPOINT}"
echo "     Bucket:     ${BUCKET}"
echo "     Region:     us-east-1"
echo "     Access Key: ${MINIO_ACCESS}"
echo "     Secret:     ${MINIO_SECRET}"
echo "     Key prefix: ftpuser/"
echo ""
echo "  4. Connecta amb FileZilla (web): https://localhost:3001"
echo "     Host: demoftp.test  Port: 21  Xifratge: TLS explicit"
echo ""
echo "  5. Verifica que els fitxers pujats apareixen al bucket:"
echo "     docker exec ${MINIO} mc ls local/${BUCKET}/ftpuser/"
echo ""
echo "  MinIO Console: http://localhost:9001  (${MINIO_ACCESS} / ${MINIO_SECRET})"
echo ""
