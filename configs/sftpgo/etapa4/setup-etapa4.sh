#!/bin/bash
# ─── setup-etapa4.sh ──────────────────────────────────────────────────────────
# Configura SFTPGo per a l'Etapa 4: autenticació OIDC via Keycloak
# S'executa des del HOST després de desplegar el lab ampliat
# Prerequisit: Etapes 1, 2 i 3 completades
set -e

LAB_NAME="sftpgo-lab"
SERVER="clab-${LAB_NAME}-server"
KEYCLOAK="clab-${LAB_NAME}-keycloak"

KEYCLOAK_URL="http://keycloak.test:8080"
KEYCLOAK_ADMIN="admin"
KEYCLOAK_PASS="admin"
REALM="lab"
CLIENT_ID="sftpgo"

echo "=== Etapa 4: Configuració Keycloak OIDC ==="
echo ""

# ─── 1. Verificar que el contenidor Keycloak existeix ────────────────────────
if ! docker ps --format '{{.Names}}' | grep -q "^${KEYCLOAK}$"; then
    echo "ERROR: El contenidor '${KEYCLOAK}' no s'ha trobat."
    echo "       Assegura't d'haver desplegat l'etapa 4: ./lab.sh deploy 4"
    echo "       (topologia: topologies/etapa4.yml)"
    exit 1
fi

echo "[etapa4] Contenidor Keycloak: $KEYCLOAK trobat."

# ─── 2. Configurar la xarxa de Keycloak ──────────────────────────────────────
echo "[etapa4] Configurant xarxa del node Keycloak..."
docker exec "$KEYCLOAK" bash -c "
    ip addr show eth1 | grep -q '10.50.0.40' && exit 0
    ip addr add 10.50.0.40/24 dev eth1 2>/dev/null || true
    ip link set eth1 up
    ip route add default via 10.50.0.1 dev eth1 2>/dev/null || true
    cat > /etc/resolv.conf << 'EOF'
nameserver 10.50.0.53
search test
options ndots:1
EOF
" 2>/dev/null || true

# ─── 3. Arrancar Keycloak en mode dev ────────────────────────────────────────
echo "[etapa4] Arrancant Keycloak en mode development..."
docker exec -d "$KEYCLOAK" \
    /opt/keycloak/bin/kc.sh start-dev \
    --http-port=8080 \
    --hostname=keycloak.test \
    --hostname-strict=false \
    --log-level=INFO

echo "[etapa4] Esperant que Keycloak arrenqui (pot trigar 45-60 s)..."
for i in $(seq 1 60); do
    if docker exec "$KEYCLOAK" curl -sf \
        "http://localhost:8080/realms/master" &>/dev/null; then
        echo "[etapa4] Keycloak disponible."
        break
    fi
    sleep 2
done

# ─── 4. Crear el realm "lab" via API de Keycloak ─────────────────────────────
echo "[etapa4] Obtenint token d'admin de Keycloak..."
ADMIN_TOKEN=$(docker exec "$KEYCLOAK" curl -sf -X POST \
    "http://localhost:8080/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli" \
    -d "username=${KEYCLOAK_ADMIN}" \
    -d "password=${KEYCLOAK_PASS}" \
    -d "grant_type=password" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null)

if [ -z "$ADMIN_TOKEN" ]; then
    echo "[etapa4] AVIS: No s'ha pogut obtenir el token d'admin automàticament."
    echo "         Configura Keycloak manualment via http://localhost:8180/admin"
else
    echo "[etapa4] Token d'admin obtingut."

    # Crear realm "lab"
    docker exec "$KEYCLOAK" curl -sf -X POST \
        "http://localhost:8080/admin/realms" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"realm\":\"${REALM}\",\"enabled\":true,\"displayName\":\"Lab FTP/FTPS\"}" \
        2>/dev/null && echo "[etapa4] Realm '${REALM}' creat." || \
        echo "[etapa4] El realm '${REALM}' ja existia o hi ha hagut un error."

    # Crear client "sftpgo"
    docker exec "$KEYCLOAK" curl -sf -X POST \
        "http://localhost:8080/admin/realms/${REALM}/clients" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
          \"clientId\": \"${CLIENT_ID}\",
          \"enabled\": true,
          \"protocol\": \"openid-connect\",
          \"publicClient\": false,
          \"directAccessGrantsEnabled\": true,
          \"standardFlowEnabled\": true,
          \"serviceAccountsEnabled\": false,
          \"redirectUris\": [\"http://demoftp.test:8080/*\"],
          \"secret\": \"sftpgo-client-secret\"
        }" 2>/dev/null && echo "[etapa4] Client '${CLIENT_ID}' creat (secret: sftpgo-client-secret)." || \
        echo "[etapa4] El client '${CLIENT_ID}' ja existia."

    # Crear usuari ftpuser
    docker exec "$KEYCLOAK" curl -sf -X POST \
        "http://localhost:8080/admin/realms/${REALM}/users" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
          \"username\": \"ftpuser\",
          \"enabled\": true,
          \"emailVerified\": true,
          \"credentials\": [{
            \"type\": \"password\",
            \"value\": \"ftppassword\",
            \"temporary\": false
          }]
        }" 2>/dev/null && echo "[etapa4] Usuari 'ftpuser' creat a Keycloak." || \
        echo "[etapa4] L'usuari 'ftpuser' ja existia."
fi

# ─── 5. Instal·lar el hook d'autenticació al servidor ────────────────────────
echo "[etapa4] Instal·lant hook d'autenticació OIDC al servidor..."
docker exec "$SERVER" bash -c "cat > /usr/local/bin/auth-keycloak.sh << 'HOOK'
#!/bin/bash
# Hook d'autenticació externa: SFTPGo → Keycloak OIDC
# SFTPGo passa les credencials via stdin en format JSON

KEYCLOAK_URL=\"http://keycloak.test:8080\"
REALM=\"lab\"
CLIENT_ID=\"sftpgo\"
CLIENT_SECRET=\"sftpgo-client-secret\"

read -r INPUT
USERNAME=\$(echo \"\$INPUT\" | python3 -c \
    \"import sys,json; d=json.load(sys.stdin); print(d.get('username',''))\" 2>/dev/null)
PASSWORD=\$(echo \"\$INPUT\" | python3 -c \
    \"import sys,json; d=json.load(sys.stdin); print(d.get('password',''))\" 2>/dev/null)

if [ -z \"\$USERNAME\" ] || [ -z \"\$PASSWORD\" ]; then
    echo '{\"username\":\"\"}'
    exit 0
fi

RESPONSE=\$(curl -sf -X POST \
    \"\${KEYCLOAK_URL}/realms/\${REALM}/protocol/openid-connect/token\" \
    -d \"client_id=\${CLIENT_ID}\" \
    -d \"client_secret=\${CLIENT_SECRET}\" \
    -d \"grant_type=password\" \
    -d \"username=\${USERNAME}\" \
    -d \"password=\${PASSWORD}\" 2>/dev/null)

ACCESS_TOKEN=\$(echo \"\$RESPONSE\" | python3 -c \
    \"import sys,json; print(json.load(sys.stdin).get('access_token',''))\" 2>/dev/null)

if [ -n \"\$ACCESS_TOKEN\" ] && [ \"\$ACCESS_TOKEN\" != \"null\" ]; then
    HOME_DIR=\"/srv/sftpgo/data/\${USERNAME}\"
    mkdir -p \"\$HOME_DIR\" 2>/dev/null || true
    echo \"{\\\"username\\\":\\\"\${USERNAME}\\\",\\\"home_dir\\\":\\\"\${HOME_DIR}\\\",\\\"permissions\\\":{\\\"/\\\":[\\\"*\\\"]},\\\"status\\\":1}\"
else
    echo '{\"username\":\"\"}'
fi
HOOK"

docker exec "$SERVER" chmod +x /usr/local/bin/auth-keycloak.sh

# ─── 6. Reconfigurar SFTPGo amb external_auth_hook ───────────────────────────
echo "[etapa4] Reconfigurando SFTPGo (etapa4 + OIDC)..."
docker exec "$SERVER" pkill sftpgo 2>/dev/null || true
sleep 2

docker exec -d "$SERVER" /usr/bin/sftpgo serve \
    --config-file /etc/sftpgo/etapa4/sftpgo.json \
    --log-level info

echo "[etapa4] SFTPGo arrancat amb external_auth_hook → Keycloak."

# ─── 7. Instruccions finals ───────────────────────────────────────────────────
echo ""
echo "=== Configuració completada ==="
echo ""
echo "  Keycloak admin:   http://localhost:8180/admin  (admin/admin)"
echo "  Realm:            lab"
echo "  Client:           sftpgo  (secret: sftpgo-client-secret)"
echo "  Usuari creat:     ftpuser / ftppassword"
echo ""
echo "  Per verificar l'autenticació OIDC des del client:"
echo "  docker exec clab-${LAB_NAME}-client curl -s -X POST \\"
echo "    'http://keycloak.test:8080/realms/lab/protocol/openid-connect/token' \\"
echo "    -d 'client_id=sftpgo' -d 'client_secret=sftpgo-client-secret' \\"
echo "    -d 'grant_type=password' -d 'username=ftpuser' -d 'password=ftppassword'"
echo ""
echo "  Connecta amb FileZilla: demoftp.test:21 (FTPES) | ftpuser/ftppassword"
echo ""
