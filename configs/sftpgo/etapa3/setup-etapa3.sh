#!/bin/bash
# ─── setup-etapa3.sh ──────────────────────────────────────────────────────────
# Configura SFTPGo per a l'Etapa 3: backend S3 amb MinIO/RustFS
# S'executa des del HOST després de desplegar el lab
# Prerequisit: Etapa 2 completada (certificats mkcert existents)
set -e

LAB_NAME="sftpgo-lab"
SERVER="clab-${LAB_NAME}-server"
CLIENT="clab-${LAB_NAME}-client"
MINIO="clab-${LAB_NAME}-rustfs"

MINIO_ENDPOINT="http://rustfs.test:9000"
MINIO_ACCESS="rustfs-access-key"
MINIO_SECRET="rustfs-secret-key"
BUCKET="sftpgo-data"

echo "=== Etapa 3: Configuració S3 (MinIO/RustFS) ==="
echo ""

# ─── 1. Verificar que el contenidor MinIO existeix ───────────────────────────
if ! docker ps --format '{{.Names}}' | grep -q "^${MINIO}$"; then
    echo "ERROR: El contenidor '${MINIO}' no s'ha trobat."
    echo "       Assegura't d'haver desplegat l'etapa 3: ./lab.sh deploy 3"
    echo "       (topologia: topologies/etapa3.yml)"
    exit 1
fi

echo "[etapa3] Contenidor MinIO: $MINIO trobat."

# ─── 2. Esperar que MinIO estigui disponible ─────────────────────────────────
echo "[etapa3] Esperant que MinIO estigui disponible..."
for i in $(seq 1 30); do
    if docker exec "$MINIO" curl -sf "${MINIO_ENDPOINT}/minio/health/live" &>/dev/null; then
        echo "[etapa3] MinIO disponible."
        break
    fi
    sleep 2
done

# ─── 3. Instal·lar mc (MinIO Client) al client ───────────────────────────────
echo "[etapa3] Instal·lant mc (MinIO Client) al contenidor client..."
docker exec "$CLIENT" bash -c "
    if ! command -v mc &>/dev/null; then
        curl -sf -Lo /usr/local/bin/mc \
            https://dl.min.io/client/mc/release/linux-amd64/mc
        chmod +x /usr/local/bin/mc
        echo 'mc instal·lat.'
    else
        echo 'mc ja instal·lat.'
    fi
"

# ─── 4. Configurar alias mc al client ────────────────────────────────────────
echo "[etapa3] Configurant alias mc al client..."
docker exec "$CLIENT" mc alias set rustfs \
    "$MINIO_ENDPOINT" "$MINIO_ACCESS" "$MINIO_SECRET" --api S3v4 2>/dev/null || true

# ─── 5. Crear el bucket sftpgo-data ──────────────────────────────────────────
echo "[etapa3] Creant bucket '${BUCKET}'..."
docker exec "$CLIENT" mc mb "rustfs/${BUCKET}" 2>/dev/null || \
    echo "[etapa3] El bucket ja existia."

docker exec "$CLIENT" mc ls rustfs/

# ─── 6. Aturar SFTPGo i arrancar amb configuració etapa3 ─────────────────────
echo "[etapa3] Reconfigurando SFTPGo (etapa3 + S3)..."
docker exec "$SERVER" pkill sftpgo 2>/dev/null || true
sleep 2

docker exec -d "$SERVER" /usr/bin/sftpgo serve \
    --config-file /etc/sftpgo/etapa3/sftpgo.json \
    --log-level info

echo "[etapa3] SFTPGo arrancat amb configuració etapa3."

# ─── 7. Instruccions per crear usuari S3 ─────────────────────────────────────
echo ""
echo "=== Passos manuals restants ==="
echo ""
echo "  1. Obre el panell d'admin SFTPGo: https://localhost:8081/web/admin"
echo "  2. Inicia sessió com admin/admin"
echo "  3. Users → Add User → configura el filesystem S3:"
echo ""
echo "     Username:   ftpuser"
echo "     Storage:    S3 Compatible"
echo "     Endpoint:   ${MINIO_ENDPOINT}"
echo "     Bucket:     ${BUCKET}"
echo "     Region:     us-east-1"
echo "     Access Key: ${MINIO_ACCESS}"
echo "     Secret:     ${MINIO_SECRET}"
echo "     Key prefix: ftpuser/"
echo ""
echo "  4. Connecta amb FileZilla (noVNC: http://localhost:8080/vnc.html)"
echo "     Host: demoftp.test  Port: 21  Xifratge: TLS explícit"
echo ""
echo "  5. Verifica que els fitxers pujats apareixen al bucket:"
echo "     docker exec clab-${LAB_NAME}-client mc ls rustfs/${BUCKET}/ftpuser/"
echo ""
