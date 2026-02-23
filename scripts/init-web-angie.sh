#!/bin/bash
# ─── init-web-angie.sh ────────────────────────────────────────────────────────
# Script d'inicialització per al node web03 (Angie — fork modern de nginx).
# Executat per containerlab via exec: un cop eth1 existeix.
set -e

NODE_IP="${NODE_IP:-10.50.0.63}"
GW_IP="${GW_IP:-10.50.0.1}"
DNS_IP="${DNS_IP:-10.50.0.53}"
IFACE="${LAN_IFACE:-eth1}"

echo "[web-angie] Configurant interfície: $IFACE → $NODE_IP/24"

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
${NODE_IP}    web03.test
10.50.0.20    server.test demoftp.test
10.50.0.53    coredns.test ns1.test
10.50.0.1     router.test
EOF

echo "[web-angie] Xarxa configurada. IP: $NODE_IP"

# Directori de contingut per defecte
mkdir -p /var/www/web03
echo "<h1>web03 (Angie) — Lab SFTPGo Etapa 6</h1>" > /var/www/web03/index.html

# Arrancada angie (el procés principal del contenidor)
exec angie -g "daemon off;"
