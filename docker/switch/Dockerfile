# ─── SWITCH: Linux bridge ─────────────────────────────────────────────────────
# Contenidor mínim amb iproute2 per crear un bridge Linux intern
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    iproute2 \
    bridge-utils \
    iputils-ping \
    net-tools \
    bash \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Script d'inici (muntat per containerlab)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
