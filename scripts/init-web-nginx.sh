#!/bin/bash
# ─── init-web-nginx.sh ────────────────────────────────────────────────────────
# Script d'inicialització per als nodes web01 i web02 (nginx).
# Executat per containerlab via exec: un cop eth1 existeix.
set -e

NODE_IP="${NODE_IP:-10.50.0.61}"
GW_IP="${GW_IP:-10.50.0.1}"
DNS_IP="${DNS_IP:-10.50.0.53}"
IFACE="${LAN_IFACE:-eth1}"

echo "[web-nginx] Configurant interfície: $IFACE → $NODE_IP/24"

for i in $(seq 1 30); do
    ip link show "$IFACE" &>/dev/null && break
    sleep 1
done

ip addr add "${NODE_IP}/24" dev "$IFACE" 2>/dev/null || true
ip link set "$IFACE" up
ip route add default via "$GW_IP" dev "$IFACE" 2>/dev/null || true

cat > /etc/resolv.conf << EOF
nameserver ${DNS_IP}
search test
options ndots:1
EOF

cat >> /etc/hosts << EOF
${NODE_IP}    $(hostname).test
10.50.0.20    server.test demoftp.test
10.50.0.53    coredns.test ns1.test
10.50.0.1     router.test
EOF

echo "[web-nginx] Xarxa configurada. IP: $NODE_IP"

# Contingut per defecte i arrancada nginx
mkdir -p /var/www/html
echo "<h1>$(hostname) — Lab SFTPGo Etapa 6</h1>" > /var/www/html/index.html

exec nginx -g "daemon off;"
