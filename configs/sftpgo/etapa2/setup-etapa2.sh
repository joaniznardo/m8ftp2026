#!/bin/bash
# ─── setup-etapa2.sh ──────────────────────────────────────────────────────────
# Genera certificats amb mkcert i configura SFTPGo per a FTPS/FTPES
# S'executa des del HOST (necessita mkcert instal·lat)
# Els certificats es copen a certs/ i es munten als contenidors
set -e

CERT_DIR="$(dirname "$0")/../../certs"
DOMAIN="demoftp.test"

echo "=== Etapa 2: Generació de certificats amb mkcert ==="
echo ""

# ─── Comprovar que mkcert és disponible ──────────────────────────────────────
if ! command -v mkcert &>/dev/null; then
    echo "ERROR: mkcert no s'ha trobat. Instal·la'l primer:"
    echo ""
    echo "  # Linux (binari directe):"
    echo "  curl -Lo /usr/local/bin/mkcert https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64"
    echo "  chmod +x /usr/local/bin/mkcert"
    echo ""
    echo "  # macOS:"
    echo "  brew install mkcert"
    echo ""
    exit 1
fi

# ─── Instal·lar la CA de mkcert al sistema ───────────────────────────────────
echo "[mkcert] Instal·lant CA local..."
mkcert -install

# ─── Obtenir el directori de la CA de mkcert ────────────────────────────────
CAROOT=$(mkcert -CAROOT)
echo "[mkcert] CA root: $CAROOT"

# ─── Generar certificats per al domini demoftp.test ─────────────────────────
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

echo "[mkcert] Generant certificats per a: $DOMAIN"
mkcert \
    -cert-file "${DOMAIN}.crt" \
    -key-file  "${DOMAIN}.key" \
    "$DOMAIN" \
    "server.test" \
    "10.50.0.20" \
    "localhost"

# ─── Copiar la CA de mkcert als certs del lab ────────────────────────────────
cp "${CAROOT}/rootCA.pem" "${CERT_DIR}/rootCA.pem"
echo "[mkcert] CA copiada a certs/rootCA.pem"

# ─── Mostrar informació dels certificats ─────────────────────────────────────
echo ""
echo "[mkcert] Certificats generats a $CERT_DIR:"
ls -la "$CERT_DIR"
echo ""
openssl x509 -in "${CERT_DIR}/${DOMAIN}.crt" -noout -text | grep -E "(Subject:|Issuer:|Not Before|Not After|DNS:|IP Address)"

echo ""
echo "=== Distribució dels certificats ==="
echo ""
echo "  Client (contenidor): /home/ftpuser/certs/"
echo "  Servidor (contenidor): /etc/sftpgo/certs/"
echo ""
echo "  NOTA: Els certificats s'instal·len automàticament via bind mount"
echo "        a cada contenidor quan arranques el lab."
echo ""
echo "=== Instal·lació de la CA als contenidors ==="
echo ""
echo "  # En el client (dins del contenidor):"
echo "  docker exec -it clab-sftpgo-lab-client bash"
echo "  cp /home/ftpuser/certs/rootCA.pem /usr/local/share/ca-certificates/mkcert-lab.crt"
echo "  update-ca-certificates"
echo ""
echo "  # En el servidor (dins del contenidor):"
echo "  docker exec -it clab-sftpgo-lab-server bash"
echo "  cp /etc/sftpgo/certs/rootCA.pem /usr/local/share/ca-certificates/mkcert-lab.crt"
echo "  update-ca-certificates"
echo ""
