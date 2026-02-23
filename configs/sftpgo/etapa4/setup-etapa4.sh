#!/bin/bash
# ─── setup-etapa4.sh ──────────────────────────────────────────────────────────
# Configura SFTPGo per a l'Etapa 4: autenticacio OIDC via Keycloak
# S'executa des del HOST despres de desplegar el lab: ./lab.sh setup 4
# Prerequisit: Etapes 1 i 2 completades (certificats mkcert existents)
#
# NOTA: Keycloak (UBI minimal) no te curl, ip ni jq dins del contenidor.
#       Totes les crides API es fan des del HOST via http://localhost:8180.
#       La xarxa de Keycloak es configura per lab.sh via nsenter.
set -e

LAB_NAME="sftpgo-lab"
SERVER="clab-${LAB_NAME}-server"
KEYCLOAK="clab-${LAB_NAME}-keycloak"

# API des del host (port mapejat 8180 -> 8080)
KEYCLOAK_HOST_URL="http://localhost:8180"
KEYCLOAK_ADMIN="admin"
KEYCLOAK_PASS="admin"
REALM="lab"
CLIENT_ID="sftpgo"
CLIENT_SECRET="sftpgo-client-secret"

echo "=== Etapa 4: Configuracio Keycloak OIDC ==="
echo ""

# ─── 1. Verificar que el contenidor Keycloak existeix ────────────────────────
if ! docker ps --format '{{.Names}}' | grep -q "^${KEYCLOAK}$"; then
    echo "ERROR: El contenidor '${KEYCLOAK}' no s'ha trobat."
    echo "       Assegura't d'haver desplegat l'etapa 4: ./lab.sh deploy 4"
    exit 1
fi

echo "[etapa4] Contenidor Keycloak: $KEYCLOAK trobat."

# ─── 2. Esperar que Keycloak estigui disponible ──────────────────────────────
# Fem health check des del HOST via el port mapejat (8180).
echo "[etapa4] Esperant que Keycloak arrenqui (pot trigar 45-60 s)..."
for i in $(seq 1 60); do
    if curl -sf "${KEYCLOAK_HOST_URL}/realms/master" &>/dev/null; then
        echo "[etapa4] Keycloak disponible (intent $i)."
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "[etapa4] AVIS: Keycloak no respon despres de 120s."
        echo "         Configura Keycloak manualment via ${KEYCLOAK_HOST_URL}/admin"
        exit 1
    fi
    sleep 2
done

# ─── 3. Obtenir token d'admin de Keycloak (des del HOST) ────────────────────
echo "[etapa4] Obtenint token d'admin de Keycloak..."
ADMIN_TOKEN=$(curl -sf -X POST \
    "${KEYCLOAK_HOST_URL}/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli" \
    -d "username=${KEYCLOAK_ADMIN}" \
    -d "password=${KEYCLOAK_PASS}" \
    -d "grant_type=password" 2>/dev/null | jq -r '.access_token // empty')

if [ -z "$ADMIN_TOKEN" ]; then
    echo "[etapa4] ERROR: No s'ha pogut obtenir el token d'admin."
    echo "         Configura Keycloak manualment via ${KEYCLOAK_HOST_URL}/admin"
    exit 1
fi

echo "[etapa4] Token d'admin obtingut."

# ─── 4. Crear el realm "lab" ─────────────────────────────────────────────────
echo "[etapa4] Creant realm '${REALM}'..."
HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' -X POST \
    "${KEYCLOAK_HOST_URL}/admin/realms" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"realm\":\"${REALM}\",\"enabled\":true,\"displayName\":\"Lab FTP/FTPS\"}" \
    2>/dev/null || echo "000")

case "$HTTP_CODE" in
    201) echo "[etapa4] Realm '${REALM}' creat." ;;
    409) echo "[etapa4] El realm '${REALM}' ja existia." ;;
    *)   echo "[etapa4] AVIS: Resultat inesperat creant realm (HTTP ${HTTP_CODE})." ;;
esac

# ─── 5. Crear client "sftpgo" ────────────────────────────────────────────────
echo "[etapa4] Creant client '${CLIENT_ID}'..."
HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' -X POST \
    "${KEYCLOAK_HOST_URL}/admin/realms/${REALM}/clients" \
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
      \"redirectUris\": [\"https://demoftp.test:8080/*\", \"https://10.50.0.20:8080/*\"],
      \"secret\": \"${CLIENT_SECRET}\"
    }" 2>/dev/null || echo "000")

case "$HTTP_CODE" in
    201) echo "[etapa4] Client '${CLIENT_ID}' creat (secret: ${CLIENT_SECRET})." ;;
    409) echo "[etapa4] El client '${CLIENT_ID}' ja existia." ;;
    *)   echo "[etapa4] AVIS: Resultat inesperat creant client (HTTP ${HTTP_CODE})." ;;
esac

# ─── 6. Crear usuari ftpuser a Keycloak ──────────────────────────────────────
echo "[etapa4] Creant usuari 'ftpuser' al realm '${REALM}'..."
HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' -X POST \
    "${KEYCLOAK_HOST_URL}/admin/realms/${REALM}/users" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"username\": \"ftpuser\",
      \"enabled\": true,
      \"firstName\": \"FTP\",
      \"lastName\": \"User\",
      \"email\": \"ftpuser@lab.test\",
      \"emailVerified\": true,
      \"credentials\": [{
        \"type\": \"password\",
        \"value\": \"ftppassword\",
        \"temporary\": false
      }]
    }" 2>/dev/null || echo "000")

case "$HTTP_CODE" in
    201) echo "[etapa4] Usuari 'ftpuser' creat a Keycloak." ;;
    409) echo "[etapa4] L'usuari 'ftpuser' ja existia." ;;
    *)   echo "[etapa4] AVIS: Resultat inesperat creant usuari (HTTP ${HTTP_CODE})." ;;
esac

# ─── 6b. Establir la contrasenya via reset-password API ──────────────────────
# En versions recents de Keycloak, les credencials inline al crear l'usuari
# poden no funcionar correctament. Forcem la contrasenya via API addicional.
echo "[etapa4] Establint contrasenya per 'ftpuser'..."
FTPUSER_ID=$(curl -sf \
    "${KEYCLOAK_HOST_URL}/admin/realms/${REALM}/users?username=ftpuser" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" 2>/dev/null | jq -r '.[0].id // empty')

if [ -n "$FTPUSER_ID" ]; then
    curl -sf -o /dev/null -X PUT \
        "${KEYCLOAK_HOST_URL}/admin/realms/${REALM}/users/${FTPUSER_ID}/reset-password" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"type":"password","value":"ftppassword","temporary":false}' \
        2>/dev/null || true
    echo "[etapa4] Contrasenya establerta."
else
    echo "[etapa4] AVIS: No s'ha trobat l'ID de l'usuari ftpuser."
fi

# ─── 7. Instal·lar el hook d'autenticacio al servidor SFTPGo ────────────────
# SFTPGo (drakkan/sftpgo) te bash, curl i jq (instal·lat per server-init.sh).
# El hook rep les credencials via stdin en format JSON i les valida contra
# Keycloak via el protocol OIDC Resource Owner Password Credentials (ROPC).
echo "[etapa4] Instal·lant hook d'autenticacio OIDC al servidor..."
docker exec "$SERVER" bash -c 'cat > /usr/local/bin/auth-keycloak.sh << '\''HOOK'\''
#!/bin/bash
# ─── Hook d autenticacio externa: SFTPGo -> Keycloak OIDC ────────────────────
# SFTPGo passa les credencials via variables d entorn:
#   SFTPGO_AUTHD_USERNAME, SFTPGO_AUTHD_PASSWORD,
#   SFTPGO_AUTHD_IP, SFTPGO_AUTHD_PROTOCOL
# El hook ha de respondre amb un JSON d usuari SFTPGo si les credencials
# son valides, o un JSON buit/error si no ho son.

KEYCLOAK_URL="http://keycloak.test:8080"
REALM="lab"
CLIENT_ID="sftpgo"
CLIENT_SECRET="sftpgo-client-secret"

USERNAME="${SFTPGO_AUTHD_USERNAME}"
PASSWORD="${SFTPGO_AUTHD_PASSWORD}"

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "{\"username\":\"\"}"
    exit 0
fi

# Validar credencials contra Keycloak via OIDC ROPC
RESPONSE=$(curl -sf -X POST \
    "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
    -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${CLIENT_SECRET}" \
    -d "grant_type=password" \
    -d "username=${USERNAME}" \
    -d "password=${PASSWORD}" 2>/dev/null || echo "")

# Comprovar si hem rebut un access_token valid
ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r ".access_token // empty" 2>/dev/null)

if [ -n "$ACCESS_TOKEN" ]; then
    HOME_DIR="/srv/sftpgo/data/${USERNAME}"
    mkdir -p "$HOME_DIR" 2>/dev/null || true
    chown 1000:1000 "$HOME_DIR" 2>/dev/null || true
    # Respondre amb un usuari SFTPGo valid (incloent password perque
    # SFTPGo pugui validar les credencials contra l hash intern)
    jq -n \
        --arg user "$USERNAME" \
        --arg pass "$PASSWORD" \
        --arg home "$HOME_DIR" \
        "{username: \$user, password: \$pass, home_dir: \$home, permissions: {\"/\": [\"*\"]}, status: 1}"
else
    echo "{\"username\":\"\"}"
fi
HOOK'

docker exec "$SERVER" chmod +x /usr/local/bin/auth-keycloak.sh

echo "[etapa4] Hook d'autenticacio instal·lat a /usr/local/bin/auth-keycloak.sh"

# ─── 8. Verificar que SFTPGo te la configuracio correcta ─────────────────────
# El sftpgo.json d'etapa4 ja te external_auth_hook configurat i esta
# bind-muntat a /etc/sftpgo/sftpgo.json. SFTPGo ja esta corrent amb
# aquesta configuracio. El hook ara existeix al path esperat.
echo ""
echo "[etapa4] NOTA: SFTPGo ja esta corrent amb la configuracio d'etapa 4."
echo "         El hook d'autenticacio s'invocara quan un usuari que no existeixi"
echo "         localment intenti connectar-se."

# ─── 9. Instruccions finals ──────────────────────────────────────────────────
echo ""
echo "=== Configuracio completada ==="
echo ""
echo "  Keycloak admin:   ${KEYCLOAK_HOST_URL}/admin  (admin/admin)"
echo "  Realm:            ${REALM}"
echo "  Client:           ${CLIENT_ID}  (secret: ${CLIENT_SECRET})"
echo "  Usuari creat:     ftpuser / ftppassword"
echo ""
echo "  Per verificar l'autenticacio OIDC des del host:"
echo "    curl -s -X POST '${KEYCLOAK_HOST_URL}/realms/${REALM}/protocol/openid-connect/token' \\"
echo "      -d 'client_id=${CLIENT_ID}' -d 'client_secret=${CLIENT_SECRET}' \\"
echo "      -d 'grant_type=password' -d 'username=ftpuser' -d 'password=ftppassword' | jq ."
echo ""
echo "  Connecta amb FileZilla: https://localhost:3001"
echo "  Host: demoftp.test  Port: 21 (FTPES) | ftpuser/ftppassword"
echo ""
echo "  SFTPGo admin: https://localhost:8081/web/admin  (admin/admin)"
echo ""
