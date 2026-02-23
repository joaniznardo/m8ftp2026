#!/bin/bash
# ─── init-client-rclone.sh ───────────────────────────────────────────────────
# Script d'inicialització per al node client-rclone (Etapa 5).
# Executat per containerlab via exec: un cop eth1 existeix.
set -e

NODE_IP="${NODE_IP:-10.50.0.12}"
GW_IP="${GW_IP:-10.50.0.1}"
DNS_IP="${DNS_IP:-10.50.0.53}"
IFACE="${LAN_IFACE:-eth1}"

echo "[client-rclone] Configurant interfície: $IFACE → $NODE_IP/24"

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
${NODE_IP}    client-rclone.test
10.50.0.20    server.test demoftp.test
10.50.0.10    client.test
10.50.0.53    coredns.test ns1.test
10.50.0.1     router.test
EOF

echo "[client-rclone] Xarxa configurada. IP: $NODE_IP, GW: $GW_IP, DNS: $DNS_IP"

mkdir -p /home/ftpuser/downloads /home/ftpuser/uploads /home/ftpuser/.config/rclone
chown -R ftpuser:ftpuser /home/ftpuser 2>/dev/null || true

echo "[client-rclone] Inicialitzacio completada."
