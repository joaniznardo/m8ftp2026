#!/bin/bash
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

RESPONSE=$(curl -sf -X POST \
    "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
    -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${CLIENT_SECRET}" \
    -d "grant_type=password" \
    -d "username=${USERNAME}" \
    -d "password=${PASSWORD}" 2>/dev/null || echo "")

ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r ".access_token // empty" 2>/dev/null)

if [ -n "$ACCESS_TOKEN" ]; then
    HOME_DIR="/srv/sftpgo/data/${USERNAME}"
    mkdir -p "$HOME_DIR" 2>/dev/null || true
    chown 1000:1000 "$HOME_DIR" 2>/dev/null || true
    jq -n \
        --arg user "$USERNAME" \
        --arg pass "$PASSWORD" \
        --arg home "$HOME_DIR" \
        "{username: \$user, password: \$pass, home_dir: \$home, permissions: {\"/\": [\"*\"]}, status: 1}"
else
    echo "{\"username\":\"\"}"
fi
