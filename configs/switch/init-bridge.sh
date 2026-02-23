#!/bin/bash
# ─── init-bridge.sh per al switch (muntat via bind) ─────────────────────────
# Quan es munta com a bind, s'executa a l'inici del contenidor switch
set -e

BRIDGE_NAME="${BRIDGE_NAME:-br-lan}"

echo "[switch] Configurant bridge Linux: $BRIDGE_NAME"
ip link add name "$BRIDGE_NAME" type bridge 2>/dev/null || true
ip link set "$BRIDGE_NAME" up

# Afegir interfícies disponibles
for IFACE in eth1 eth2 eth3 eth4 eth5 eth6 eth7 eth8 eth9 eth10 eth11 eth12; do
    if ip link show "$IFACE" &>/dev/null; then
        ip link set "$IFACE" up
        ip link set "$IFACE" master "$BRIDGE_NAME" 2>/dev/null || true
        echo "[switch] $IFACE → $BRIDGE_NAME"
    fi
done

echo "[switch] Bridge configurat."
bridge link show 2>/dev/null || true
