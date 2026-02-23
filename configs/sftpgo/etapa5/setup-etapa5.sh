#!/bin/bash
# ─── setup-etapa5.sh ──────────────────────────────────────────────────────────
# Configura l'Etapa 5: clients textuals (lftp, rclone) en nodes separats
# S'executa des del HOST després de desplegar el lab amb els nous nodes actius.
# Prerequisit: Etapa 2 completada (certificats mkcert existents)
set -e

LAB_NAME="sftpgo-lab"
SERVER="clab-${LAB_NAME}-server"
CLIENT_LFTP="clab-${LAB_NAME}-client-lftp"
CLIENT_RCLONE="clab-${LAB_NAME}-client-rclone"

FTP_HOST="demoftp.test"
FTP_USER="ftpuser"
FTP_PASS="ftppassword"
CERT_PATH="/home/ftpuser/certs/rootCA.pem"

echo "=== Etapa 5: Clients textuals FTP (lftp + rclone) ==="
echo ""

# ─── 1. Verificar que els contenidors existeixen ──────────────────────────────
for container in "$CLIENT_LFTP" "$CLIENT_RCLONE"; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "ERROR: El contenidor '${container}' no s'ha trobat."
        echo "       Assegura't d'haver desplegat l'etapa 5: ./lab.sh deploy 5"
        echo "       (topologia: topologies/etapa5.yml)"
        exit 1
    fi
    echo "[etapa5] Contenidor trobat: ${container}"
done

# ─── 2. Verificar que el servidor FTP funciona ────────────────────────────────
echo "[etapa5] Comprovant que SFTPGo és accessible..."
if ! docker exec "$SERVER" ss -tlnp 2>/dev/null | grep -q ":21"; then
    echo "WARN: SFTPGo pot no estar escoltant al port 21. Continua igualment."
fi

# ─── 3. Configurar client-lftp ────────────────────────────────────────────────
echo "[etapa5] Configurant client-lftp..."

# Crear fitxer de configuració lftp
docker exec "$CLIENT_LFTP" bash -c "
    mkdir -p /home/ftpuser/.lftp
    cat > /home/ftpuser/.lftp/rc << 'LFTPRC'
# ─── Configuració lftp per al lab ────────────────────────────────
set ftp:ssl-allow yes
set ftp:ssl-force yes
set ftp:ssl-protect-data yes
set ftp:ssl-protect-list yes
set ssl:verify-certificate yes
set ssl:ca-file /home/ftpuser/certs/rootCA.pem
set ftp:passive-mode yes
set net:max-retries 3
set net:reconnect-interval-base 5
set net:timeout 30
set cmd:interactive true
LFTPRC
    chown -R ftpuser:ftpuser /home/ftpuser/.lftp
    echo '[lftp] Configuració creada a /home/ftpuser/.lftp/rc'
"

# Crear script d'exemples lftp
docker exec "$CLIENT_LFTP" bash -c "
    cat > /home/ftpuser/demo-lftp.sh << 'DEMO'
#!/bin/bash
# ─── demo-lftp.sh — Exemples d'ús de lftp ────────────────────────────────────
FTP_HOST=\"demoftp.test\"
FTP_USER=\"ftpuser\"
FTP_PASS=\"ftppassword\"

echo '=== Demo lftp — Etapa 5 ==='
echo ''

echo '--- 1. Llistar directori remot ---'
lftp -u \"\$FTP_USER\",\"\$FTP_PASS\" \"\$FTP_HOST\" -e \"ls; bye\" 2>&1 || true

echo ''
echo '--- 2. Crear directori remot ---'
lftp -u \"\$FTP_USER\",\"\$FTP_PASS\" \"\$FTP_HOST\" -e \"mkdir -p demos; bye\" 2>&1 || true

echo ''
echo '--- 3. Pujar un fitxer ---'
echo 'Hola des de lftp!' > /tmp/prova-lftp.txt
lftp -u \"\$FTP_USER\",\"\$FTP_PASS\" \"\$FTP_HOST\" -e \"put /tmp/prova-lftp.txt -o demos/prova-lftp.txt; bye\" 2>&1 || true

echo ''
echo '--- 4. Descarregar un fitxer ---'
lftp -u \"\$FTP_USER\",\"\$FTP_PASS\" \"\$FTP_HOST\" -e \"get demos/prova-lftp.txt -o /tmp/descarregat-lftp.txt; bye\" 2>&1 || true
cat /tmp/descarregat-lftp.txt 2>/dev/null || true

echo ''
echo '--- 5. Mirall (mirror) del directori remot ---'
mkdir -p /tmp/mirall-ftp
lftp -u \"\$FTP_USER\",\"\$FTP_PASS\" \"\$FTP_HOST\" -e \"mirror / /tmp/mirall-ftp; bye\" 2>&1 || true
ls -la /tmp/mirall-ftp/ 2>/dev/null || true

echo ''
echo '=== Fi de la demo lftp ==='
DEMO
    chmod +x /home/ftpuser/demo-lftp.sh
    chown ftpuser:ftpuser /home/ftpuser/demo-lftp.sh
    echo '[lftp] Script de demo creat a /home/ftpuser/demo-lftp.sh'
"

echo "[etapa5] client-lftp configurat."

# ─── 4. Configurar client-rclone ─────────────────────────────────────────────
echo "[etapa5] Configurant client-rclone..."

# Crear fitxer de configuració rclone per a FTP amb TLS
docker exec "$CLIENT_RCLONE" bash -c "
    mkdir -p /home/ftpuser/.config/rclone
    cat > /home/ftpuser/.config/rclone/rclone.conf << 'RCLONECONF'
[demoftp]
type = ftp
host = demoftp.test
port = 21
user = ftpuser
pass = \$(rclone obscure ftppassword 2>/dev/null || echo '')
tls = false
explicit_tls = true
no_check_certificate = false
disable_tls13 = false
concurrency = 4
skip_inaccessible_subdirs = false
RCLONECONF
    echo '[rclone] Config base creada. Generant contrasenya ofuscada...'
    OBSCURED=\$(rclone obscure ftppassword 2>/dev/null || echo 'ERROR')
    sed -i \"s|pass = .*|pass = \${OBSCURED}|\" /home/ftpuser/.config/rclone/rclone.conf
    chown -R ftpuser:ftpuser /home/ftpuser/.config
    echo '[rclone] Configuració creada a /home/ftpuser/.config/rclone/rclone.conf'
"

# Crear script d'exemples rclone
docker exec "$CLIENT_RCLONE" bash -c "
    cat > /home/ftpuser/demo-rclone.sh << 'DEMO'
#!/bin/bash
# ─── demo-rclone.sh — Exemples d'ús de rclone ────────────────────────────────
REMOTE=\"demoftp:\"

echo '=== Demo rclone — Etapa 5 ==='
echo ''

echo '--- 1. Llistar remot ---'
rclone ls \"\$REMOTE\" 2>&1 || true

echo ''
echo '--- 2. Crear directori i pujar fitxer ---'
echo 'Hola des de rclone!' > /tmp/prova-rclone.txt
rclone copy /tmp/prova-rclone.txt \"\${REMOTE}demos/\" 2>&1 || true

echo ''
echo '--- 3. Llistar directori remot ---'
rclone ls \"\${REMOTE}demos/\" 2>&1 || true

echo ''
echo '--- 4. Descarregar fitxer ---'
mkdir -p /tmp/descàrrega-rclone
rclone copy \"\${REMOTE}demos/prova-rclone.txt\" /tmp/descàrrega-rclone/ 2>&1 || true
cat /tmp/descàrrega-rclone/prova-rclone.txt 2>/dev/null || true

echo ''
echo '--- 5. Sincronitzar carpeta local → remota ---'
mkdir -p /tmp/local-sync
echo 'Fitxer 1' > /tmp/local-sync/f1.txt
echo 'Fitxer 2' > /tmp/local-sync/f2.txt
rclone sync /tmp/local-sync/ \"\${REMOTE}sync-demo/\" 2>&1 || true
rclone ls \"\${REMOTE}sync-demo/\" 2>&1 || true

echo ''
echo '=== Fi de la demo rclone ==='
DEMO
    chmod +x /home/ftpuser/demo-rclone.sh
    chown ftpuser:ftpuser /home/ftpuser/demo-rclone.sh
    echo '[rclone] Script de demo creat a /home/ftpuser/demo-rclone.sh'
"

echo "[etapa5] client-rclone configurat."

# ─── 5. Verificació bàsica de connectivitat ──────────────────────────────────
echo ""
echo "[etapa5] Verificant connectivitat DNS des dels clients..."
docker exec "$CLIENT_LFTP" bash -c "dig ${FTP_HOST} +short 2>/dev/null || nslookup ${FTP_HOST} 2>/dev/null || true"
docker exec "$CLIENT_RCLONE" bash -c "dig ${FTP_HOST} +short 2>/dev/null || nslookup ${FTP_HOST} 2>/dev/null || true"

# ─── 6. Instruccions finals ───────────────────────────────────────────────────
echo ""
echo "=== Etapa 5 configurada. Passos de verificació ==="
echo ""
echo "  CLIENT LFTP (clab-${LAB_NAME}-client-lftp):"
echo "    docker exec -it ${CLIENT_LFTP} bash"
echo "    # Interactiu:"
echo "    lftp -u ${FTP_USER},${FTP_PASS} ${FTP_HOST}"
echo "    # Demo automàtic:"
echo "    bash /home/ftpuser/demo-lftp.sh"
echo ""
echo "  CLIENT RCLONE (clab-${LAB_NAME}-client-rclone):"
echo "    docker exec -it ${CLIENT_RCLONE} bash"
echo "    # Llistat interactiu:"
echo "    rclone ls demoftp:"
echo "    # Demo automàtic:"
echo "    bash /home/ftpuser/demo-rclone.sh"
echo ""
echo "  CLIENTS ONLINE SEGURS (accés des del host):"
echo "    - filestash.app  → https://www.filestash.app  (self-hosted, FTPS)"
echo "    - net2ftp        → https://www.net2ftp.com    (FTPS suportat)"
echo ""
