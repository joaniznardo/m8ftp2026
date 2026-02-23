#!/bin/bash
# ─── init-proxy.sh ────────────────────────────────────────────────────────────
# Script d'inicialització per al node proxy (nginx proxy invers).
# Executat per containerlab via exec: un cop eth1 existeix.
set -e

NODE_IP="${NODE_IP:-10.50.0.60}"
GW_IP="${GW_IP:-10.50.0.1}"
DNS_IP="${DNS_IP:-10.50.0.53}"
IFACE="${LAN_IFACE:-eth1}"

echo "[proxy] Configurant interfície: $IFACE → $NODE_IP/24"

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
${NODE_IP}    proxy.test
10.50.0.20    server.test demoftp.test
10.50.0.61    web01.test web01.demoftp.test
10.50.0.62    web02.test web02.demoftp.test
10.50.0.63    web03.test web03.demoftp.test
10.50.0.53    coredns.test ns1.test
10.50.0.1     router.test
EOF

echo "[proxy] Xarxa configurada. IP: $NODE_IP"

# Configuració nginx proxy invers
cat > /etc/nginx/sites-available/proxy-lab << 'PROXY'
# ─── Proxy invers — Etapa 6 ──────────────────────────────────────────────────

server {
    listen 80;
    server_name web01.demoftp.test;
    location / {
        proxy_pass         http://10.50.0.61:80;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
    add_header X-Proxy "nginx-proxy" always;
}

server {
    listen 80;
    server_name web02.demoftp.test;
    location / {
        proxy_pass         http://10.50.0.62:80;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
    add_header X-Proxy "nginx-proxy" always;
}

server {
    listen 80;
    server_name web03.demoftp.test;
    location / {
        proxy_pass         http://10.50.0.63:80;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
    add_header X-Proxy "nginx-proxy" always;
}
PROXY

mkdir -p /etc/nginx/sites-enabled
ln -sf /etc/nginx/sites-available/proxy-lab /etc/nginx/sites-enabled/proxy-lab
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

nginx -t && exec nginx -g "daemon off;"
