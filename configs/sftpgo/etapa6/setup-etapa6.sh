#!/bin/bash
# ─── setup-etapa6.sh ──────────────────────────────────────────────────────────
# Configura l'Etapa 6: proxy invers (nginx + angie) que serveix web01/web02/web03
# on el contingut de cada web prové d'un directori al servidor FTP (SFTPGo).
# S'executa des del HOST un cop el lab ha estat redesplegar amb els nous nodes.
# Compatible amb Etapa 1 (FTP pla) i Etapa 2+ (FTPES/FTPS amb TLS).
# Detecta automàticament si SFTPGo usa TLS i adapta els paràmetres lftp.
set -e

LAB_NAME="sftpgo-lab"
SERVER="clab-${LAB_NAME}-server"
PROXY="clab-${LAB_NAME}-proxy"
WEB01="clab-${LAB_NAME}-web01"
WEB02="clab-${LAB_NAME}-web02"
WEB03="clab-${LAB_NAME}-web03"

FTP_HOST="demoftp.test"
FTP_USER="ftpuser"
FTP_PASS="ftppassword"
CERT_PATH="/home/ftpuser/certs/rootCA.pem"

echo "=== Etapa 6: Proxy invers + webs des del contingut FTP ==="
echo ""

# ─── 1. Verificar que tots els contenidors existeixen ────────────────────────
for container in "$SERVER" "$PROXY" "$WEB01" "$WEB02" "$WEB03"; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "ERROR: El contenidor '${container}' no s'ha trobat."
        echo "       Assegura't d'haver desplegat l'etapa 6: ./lab.sh deploy 6"
        echo "       (topologia: topologies/etapa6.yml)"
        exit 1
    fi
    echo "[etapa6] Contenidor trobat: ${container}"
done

# ─── 1b. Detectar mode TLS del servidor FTP ──────────────────────────────────
echo "[etapa6] Detectant mode TLS del servidor FTP..."
TLS_MODE=$(docker exec "$SERVER" bash -c \
    'grep -o "\"tls_mode\"[[:space:]]*:[[:space:]]*[0-9]*" /etc/sftpgo/sftpgo.json 2>/dev/null \
     | head -1 | grep -o "[0-9]*$"' 2>/dev/null || echo "0")

# Si no es pot determinar, assumir mode 0 (sense TLS)
TLS_MODE="${TLS_MODE:-0}"
echo "[etapa6] TLS mode detectat: ${TLS_MODE}"

if [ "$TLS_MODE" -gt 0 ] 2>/dev/null; then
    USE_TLS="yes"
    echo "[etapa6] TLS actiu → lftp usarà connexions xifrades (FTPES/FTPS)"
    LFTP_SSL_SETTINGS='set ftp:ssl-allow yes
set ftp:ssl-force yes
set ftp:ssl-protect-data yes
set ftp:ssl-protect-list yes
set ssl:verify-certificate yes
set ssl:ca-file /tmp/rootCA.pem'

    # Copiar el certificat CA als contenidors web
    echo "[etapa6] Copiant certificat rootCA.pem als contenidors web..."
    for container in "$WEB01" "$WEB02" "$WEB03"; do
        docker cp "${SERVER}:/etc/sftpgo/certs/rootCA.pem" "/tmp/rootCA-etapa6.pem" 2>/dev/null || \
            docker cp "${SERVER}:${CERT_PATH}" "/tmp/rootCA-etapa6.pem" 2>/dev/null || true
        if [ -f "/tmp/rootCA-etapa6.pem" ]; then
            docker cp "/tmp/rootCA-etapa6.pem" "${container}:/tmp/rootCA.pem"
            echo "[etapa6] rootCA.pem copiat a ${container}:/tmp/rootCA.pem"
        fi
    done
    rm -f "/tmp/rootCA-etapa6.pem" 2>/dev/null || true
else
    USE_TLS="no"
    echo "[etapa6] TLS inactiu → lftp usarà FTP pla"
    LFTP_SSL_SETTINGS='set ftp:ssl-allow no'
fi

# ─── 2. Crear contingut web als directoris FTP del servidor ──────────────────
echo "[etapa6] Creant contingut web als directoris FTP del servidor..."

docker exec "$SERVER" bash -c "
    FTP_HOME=\"/srv/sftpgo/data/ftpuser\"
    mkdir -p \"\${FTP_HOME}/web01\" \"\${FTP_HOME}/web02\" \"\${FTP_HOME}/web03\"

    # Contingut web01
    cat > \"\${FTP_HOME}/web01/index.html\" << 'HTML'
<!DOCTYPE html>
<html lang=\"ca\">
<head><meta charset=\"utf-8\"><title>Web 01 — Lab SFTPGo</title>
<style>body{font-family:sans-serif;background:#0e0d1f;color:#e8e8f0;text-align:center;padding:60px}
h1{color:#30efbc}p{color:#8884bb}code{background:#16153a;padding:3px 8px;border-radius:4px}</style>
</head>
<body>
<h1>Web 01</h1>
<p>Contingut servit per <strong>nginx</strong> via proxy invers des de SFTPGo FTP.</p>
<p>Directori FTP: <code>/web01/</code></p>
<p>Host: <code>web01.demoftp.test</code></p>
</body>
</html>
HTML

    # Contingut web02
    cat > \"\${FTP_HOME}/web02/index.html\" << 'HTML'
<!DOCTYPE html>
<html lang=\"ca\">
<head><meta charset=\"utf-8\"><title>Web 02 — Lab SFTPGo</title>
<style>body{font-family:sans-serif;background:#0e0d1f;color:#e8e8f0;text-align:center;padding:60px}
h1{color:#30efbc}p{color:#8884bb}code{background:#16153a;padding:3px 8px;border-radius:4px}</style>
</head>
<body>
<h1>Web 02</h1>
<p>Contingut servit per <strong>nginx</strong> via proxy invers des de SFTPGo FTP.</p>
<p>Directori FTP: <code>/web02/</code></p>
<p>Host: <code>web02.demoftp.test</code></p>
</body>
</html>
HTML

    # Contingut web03
    cat > \"\${FTP_HOME}/web03/index.html\" << 'HTML'
<!DOCTYPE html>
<html lang=\"ca\">
<head><meta charset=\"utf-8\"><title>Web 03 — Lab SFTPGo</title>
<style>body{font-family:sans-serif;background:#0e0d1f;color:#e8e8f0;text-align:center;padding:60px}
h1{color:#30efbc}p{color:#8884bb}code{background:#16153a;padding:3px 8px;border-radius:4px}</style>
</head>
<body>
<h1>Web 03</h1>
<p>Contingut servit per <strong>Angie</strong> (fork nginx rus) via proxy invers des de SFTPGo FTP.</p>
<p>Directori FTP: <code>/web03/</code></p>
<p>Host: <code>web03.demoftp.test</code></p>
</body>
</html>
HTML

    chown -R sftpgo:sftpgo \"\${FTP_HOME}\" 2>/dev/null || true
    chmod -R 755 \"\${FTP_HOME}/web01\" \"\${FTP_HOME}/web02\" \"\${FTP_HOME}/web03\"
    echo '[etapa6] Contingut web creat als directoris FTP'
    ls -la \"\${FTP_HOME}/\"
"

# ─── 3. Configurar web01 (nginx) ─────────────────────────────────────────────
echo "[etapa6] Configurant web01 (nginx)..."

docker exec "$WEB01" bash -c "
    apt-get install -y --no-install-recommends lftp 2>/dev/null || true

    # Crear directori de contingut
    mkdir -p /var/www/web01

    # Descarregar contingut via LFTP des del servidor FTP
    lftp -u ftpuser,ftppassword demoftp.test << 'LFTP_CMD' 2>/dev/null || true
set ftp:passive-mode yes
${LFTP_SSL_SETTINGS}
mirror /web01/ /var/www/web01/
bye
LFTP_CMD

    # Configuració nginx per a web01
    cat > /etc/nginx/sites-available/web01 << 'NGINX'
server {
    listen 80;
    server_name web01.demoftp.test;

    root /var/www/web01;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Afegir capçalera personalitzada
    add_header X-Served-By \"nginx-web01\" always;
    add_header X-Lab-Stage \"etapa6\" always;
}
NGINX

    ln -sf /etc/nginx/sites-available/web01 /etc/nginx/sites-enabled/web01
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    nginx -t && nginx -s reload 2>/dev/null || nginx -t && service nginx start || true
    echo '[web01] nginx configurat i iniciat'
"

# ─── 4. Configurar web02 (nginx) ─────────────────────────────────────────────
echo "[etapa6] Configurant web02 (nginx)..."

docker exec "$WEB02" bash -c "
    apt-get install -y --no-install-recommends lftp 2>/dev/null || true

    mkdir -p /var/www/web02

    lftp -u ftpuser,ftppassword demoftp.test << 'LFTP_CMD' 2>/dev/null || true
set ftp:passive-mode yes
${LFTP_SSL_SETTINGS}
mirror /web02/ /var/www/web02/
bye
LFTP_CMD

    cat > /etc/nginx/sites-available/web02 << 'NGINX'
server {
    listen 80;
    server_name web02.demoftp.test;

    root /var/www/web02;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    add_header X-Served-By \"nginx-web02\" always;
    add_header X-Lab-Stage \"etapa6\" always;
}
NGINX

    ln -sf /etc/nginx/sites-available/web02 /etc/nginx/sites-enabled/web02
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    nginx -t && nginx -s reload 2>/dev/null || nginx -t && service nginx start || true
    echo '[web02] nginx configurat i iniciat'
"

# ─── 5. Configurar web03 (angie) ─────────────────────────────────────────────
echo "[etapa6] Configurant web03 (angie)..."

docker exec "$WEB03" bash -c "
    # Angie ja esta instal·lat (a la imatge sftpgo-lab/web-angie:latest)
    # La imatge web-angie es Alpine, lftp ja esta inclosa al Dockerfile
    # No cal instal·lar res addicional

    mkdir -p /var/www/web03

    lftp -u ftpuser,ftppassword demoftp.test << 'LFTP_CMD' 2>/dev/null || true
set ftp:passive-mode yes
${LFTP_SSL_SETTINGS}
mirror /web03/ /var/www/web03/
bye
LFTP_CMD

    cat > /etc/angie/http.d/web03.conf << 'ANGIE'
server {
    listen 80;
    server_name web03.demoftp.test;

    root /var/www/web03;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    add_header X-Served-By \"angie-web03\" always;
    add_header X-Lab-Stage \"etapa6\" always;
    add_header X-Powered-By \"Angie\" always;
}
ANGIE

    angie -t && (angie -s reload 2>/dev/null || angie 2>/dev/null || true)
    echo '[web03] Angie configurat i iniciat'
"

# ─── 6. Configurar proxy invers (nginx) ──────────────────────────────────────
echo "[etapa6] Configurant el proxy invers principal (nginx)..."

docker exec "$PROXY" bash -c "
    cat > /etc/nginx/sites-available/proxy-lab << 'PROXY'
# ─── Proxy invers — Etapa 6 ────────────────────────────────────────────────

# web01 → nginx intern (10.50.0.61)
server {
    listen 80;
    server_name web01.demoftp.test;

    location / {
        proxy_pass http://10.50.0.61:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    add_header X-Proxy \"nginx-proxy\" always;
}

# web02 → nginx intern (10.50.0.62)
server {
    listen 80;
    server_name web02.demoftp.test;

    location / {
        proxy_pass http://10.50.0.62:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    add_header X-Proxy \"nginx-proxy\" always;
}

# web03 → angie intern (10.50.0.63)
server {
    listen 80;
    server_name web03.demoftp.test;

    location / {
        proxy_pass http://10.50.0.63:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    add_header X-Proxy \"nginx-proxy\" always;
}
PROXY

    ln -sf /etc/nginx/sites-available/proxy-lab /etc/nginx/sites-enabled/proxy-lab
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    nginx -t && nginx -s reload 2>/dev/null || nginx -t && service nginx start || true
    echo '[proxy] nginx proxy invers configurat i iniciat'
"

# ─── 7. Verificació ──────────────────────────────────────────────────────────
echo ""
echo "[etapa6] Verificant que el proxy respon als tres vhosts..."
sleep 2

for vhost in web01 web02 web03; do
    response=$(docker exec "$PROXY" curl -sf -o /dev/null -w "%{http_code}" \
        -H "Host: ${vhost}.demoftp.test" "http://127.0.0.1/" 2>/dev/null || echo "ERR")
    echo "[etapa6] ${vhost}.demoftp.test → HTTP ${response}"
done

# ─── 8. Instruccions finals ───────────────────────────────────────────────────
echo ""
echo "=== Etapa 6 configurada. Verificació ==="
echo ""
echo "  Des del host:"
echo "    curl -H 'Host: web01.demoftp.test' http://localhost:8091"
echo "    curl -H 'Host: web02.demoftp.test' http://localhost:8091"
echo "    curl -H 'Host: web03.demoftp.test' http://localhost:8091"
echo ""
echo "  Afegir al /etc/hosts del host per navegació directa:"
echo "    127.0.0.1   web01.demoftp.test web02.demoftp.test web03.demoftp.test"
echo ""
echo "  Actualitzar contingut via FTP i sincronitzar:"
echo "    docker exec ${WEB01} lftp -u ftpuser,ftppassword demoftp.test -e 'mirror /web01/ /var/www/web01/; bye'"
echo ""
