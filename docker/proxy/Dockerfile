# ─── PROXY: nginx proxy invers per a web01/web02/web03 ───────────────────────
# Ubuntu 24.04 + nginx com a proxy invers (virtual host per nom de host)
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Madrid

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Xarxa i diagnosi
    iproute2 \
    iputils-ping \
    net-tools \
    curl \
    wget \
    ca-certificates \
    dnsutils \
    # Proxy invers
    nginx \
    # Eines
    openssl \
    nano \
    bash \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Eliminar la configuració per defecte de nginx
RUN rm -f /etc/nginx/sites-enabled/default

# La configuració del proxy es crea per init-proxy.sh via exec:
RUN mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# HTTP proxy (web01/web02/web03 per Server Name)
EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
