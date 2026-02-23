# ─── WEB-NGINX: servidor web nginx per a web01 i web02 ───────────────────────
# Ubuntu 24.04 + nginx + lftp (per descarregar contingut des del servidor FTP)
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
    # Servidor web
    nginx \
    # Client FTP per sincronitzar contingut
    lftp \
    ftp \
    # Eines
    openssl \
    nano \
    bash \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Directori de contingut (el contingut el proveeix el setup script)
RUN mkdir -p /var/www/html /var/www/web01 /var/www/web02 && \
    chown -R www-data:www-data /var/www

# Fitxer de benvinguda per defecte (substituït per setup-etapa6.sh)
RUN echo "<h1>Lab SFTPGo - Etapa 6 (nginx)</h1>" > /var/www/html/index.html

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# HTTP (nginx)
EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
