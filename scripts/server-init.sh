#!/bin/bash
# ─── server-init.sh ───────────────────────────────────────────────────────────
# Executat per containerlab via exec: dins del contenidor drakkan/sftpgo.
# Configura la xarxa LAN i crea l'usuari FTP via API REST.
# Nota: drakkan/sftpgo ja arrenca SFTPGo automàticament (entrypoint de la imatge).
# L'script s'executa com a root via docker exec.
set -e

SERVER_IP="${SERVER_IP:-10.50.0.20}"
GW_IP="${GW_IP:-10.50.0.1}"
DNS_IP="${DNS_IP:-10.50.0.53}"
IFACE="${LAN_IFACE:-eth1}"
ADMIN_PORT="${ADMIN_PORT:-8080}"

echo "[server] Instal·lant eines de xarxa..."
apt-get update -qq && apt-get install -y --no-install-recommends \
    iproute2 iputils-ping dnsutils curl jq \
    2>/dev/null || true
rm -rf /var/lib/apt/lists/*

echo "[server] Configurant interfície: $IFACE → $SERVER_IP/24"

# Esperar que la interfície aparega (containerlab la crea just abans de exec:)
for i in $(seq 1 30); do
    ip link show "$IFACE" &>/dev/null && break
    sleep 1
done

# Configurar IP + ruta per defecte
ip addr add "${SERVER_IP}/24" dev "$IFACE" 2>/dev/null || true
ip link set "$IFACE" up
ip route add default via "$GW_IP" dev "$IFACE" 2>/dev/null || true

# DNS → CoreDNS
cat > /etc/resolv.conf << EOF
nameserver ${DNS_IP}
search test
options ndots:1
EOF

# /etc/hosts de suport
cat >> /etc/hosts << EOF
${SERVER_IP}    server.test demoftp.test
10.50.0.10      client.test
10.50.0.53      coredns.test ns1.test
10.50.0.1       router.test
EOF

echo "[server] Xarxa configurada. IP: $SERVER_IP, GW: $GW_IP, DNS: $DNS_IP"

# ─── Crear l'usuari FTP via API REST (en segon pla) ──────────────────────────
# SFTPGo ja està arrencant via l'entrypoint de la imatge.
# Esperem que estigui llest i creem l'usuari ftpuser.
# NOTA: NO usem set -e dins de la subshell — gestionem errors explícitament.
(
    echo "[server] Esperant que SFTPGo estigui disponible..."

    # Detectar si l'admin API usa HTTPS o HTTP.
    # Provem primer HTTPS (etapes 2+), si falla, provem HTTP (etapa 1).
    # Usem -k per acceptar certificats autosignats (mkcert).
    API_BASE=""
    for i in $(seq 1 60); do
        if curl -skf "https://127.0.0.1:${ADMIN_PORT}/api/v2/token" \
            -u admin:admin > /dev/null 2>&1; then
            API_BASE="https://127.0.0.1:${ADMIN_PORT}"
            echo "[server] SFTPGo operatiu via HTTPS (intent $i)"
            break
        elif curl -sf "http://127.0.0.1:${ADMIN_PORT}/api/v2/token" \
            -u admin:admin > /dev/null 2>&1; then
            API_BASE="http://127.0.0.1:${ADMIN_PORT}"
            echo "[server] SFTPGo operatiu via HTTP (intent $i)"
            break
        fi
        sleep 2
    done

    if [ -z "$API_BASE" ]; then
        echo "[server] AVÍS: SFTPGo no respon després de 120s. L'usuari FTP s'haurà de crear manualment."
        exit 0
    fi

    # Opcions de curl: -k per HTTPS amb certs autosignats
    CURL_OPTS="-sk"

    # Obtenir token JWT de l'admin
    TOKEN=$(curl ${CURL_OPTS} -X GET "${API_BASE}/api/v2/token" \
        -u admin:admin 2>/dev/null | jq -r '.access_token // empty')

    if [ -z "$TOKEN" ]; then
        echo "[server] AVÍS: No s'ha pogut obtenir token admin. L'usuari FTP s'haurà de crear manualment."
        exit 0
    fi

    echo "[server] Token admin obtingut correctament."

    # Comprovar si l'usuari ja existeix (sense -f per evitar que un 404 mate la subshell)
    USER_HTTP=$(curl ${CURL_OPTS} -o /dev/null -w '%{http_code}' \
        "${API_BASE}/api/v2/users/ftpuser" \
        -H "Authorization: Bearer ${TOKEN}" 2>/dev/null || echo "000")

    if [ "$USER_HTTP" = "200" ]; then
        echo "[server] L'usuari ftpuser ja existeix."
    else
        echo "[server] Creant usuari FTP: ftpuser (HTTP check: $USER_HTTP)..."
        # Assegurar directori home
        mkdir -p /srv/sftpgo/data/ftpuser 2>/dev/null || true
        chown 1000:1000 /srv/sftpgo/data/ftpuser 2>/dev/null || true

        CREATE_HTTP=$(curl ${CURL_OPTS} -o /dev/null -w '%{http_code}' \
            -X POST "${API_BASE}/api/v2/users" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d '{
                "username": "ftpuser",
                "password": "ftppassword",
                "status": 1,
                "home_dir": "/srv/sftpgo/data/ftpuser",
                "permissions": {
                    "/": ["*"]
                }
            }' 2>/dev/null || echo "000")

        if [ "$CREATE_HTTP" = "201" ]; then
            echo "[server] Usuari ftpuser creat correctament (HTTP $CREATE_HTTP)."
        else
            echo "[server] AVÍS: Error creant ftpuser (HTTP $CREATE_HTTP). Crea'l manualment des de l'admin web."
        fi
    fi
) &

echo "[server] Inicialització completada. SFTPGo arrencant en segon pla."
