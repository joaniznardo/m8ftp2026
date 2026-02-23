#!/bin/bash
# ─── client-init.sh ───────────────────────────────────────────────────────────
# Executat per containerlab via exec: dins del contenidor linuxserver/filezilla.
# Configura la xarxa LAN. El VNC/web UI ja arrenca sol via s6-overlay.
# Nota: linuxserver/filezilla és Alpine (apk), no Ubuntu (apt).
set -e

CLIENT_IP="${CLIENT_IP:-10.50.0.10}"
GW_IP="${GW_IP:-10.50.0.1}"
DNS_IP="${DNS_IP:-10.50.0.53}"
IFACE="${LAN_IFACE:-eth1}"

echo "[client] Instal·lant eines de xarxa (Alpine)..."
apk add --no-cache iproute2 iputils bind-tools curl 2>/dev/null || true

echo "[client] Configurant interfície: $IFACE → $CLIENT_IP/24"

# Esperar que la interfície aparega (containerlab la crea just abans de exec:)
for i in $(seq 1 30); do
    ip link show "$IFACE" &>/dev/null && break
    sleep 1
done

# Configurar IP + ruta per defecte
ip addr add "${CLIENT_IP}/24" dev "$IFACE" 2>/dev/null || true
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
${CLIENT_IP}    client.test
10.50.0.20      server.test demoftp.test
10.50.0.53      coredns.test ns1.test
10.50.0.1       router.test
EOF

echo "[client] Xarxa configurada. IP: $CLIENT_IP, GW: $GW_IP, DNS: $DNS_IP"
echo "[client] FileZilla accessible via web a https://localhost:3001/"
