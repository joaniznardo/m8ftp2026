#!/bin/bash
# ─── router-init.sh per al contenidor FRR ────────────────────────────────────
set -e

LAN_IFACE="${LAN_IFACE:-eth1}"
LAN_IP="${LAN_IP:-10.50.0.1/24}"

echo "[router] Configurant interfície LAN: $LAN_IFACE → $LAN_IP"

# Esperar interfície
for i in $(seq 1 30); do
    ip link show "$LAN_IFACE" &>/dev/null && break
    sleep 1
done

# Configurar IP a la LAN
ip addr add "$LAN_IP" dev "$LAN_IFACE" 2>/dev/null || true
ip link set "$LAN_IFACE" up

# Habilitar IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

# /etc/hosts
cat >> /etc/hosts << EOF
10.50.0.1       router.test
10.50.0.10      client.test
10.50.0.20      server.test demoftp.test
10.50.0.53      coredns.test ns1.test
EOF

echo "[router] Interfície LAN configurada. FRR ja s'executa via l'entrypoint de la imatge."
