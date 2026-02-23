# ─── WEB-ANGIE: servidor web Angie per a web03 ───────────────────────────────
# Imatge oficial Angie (Alpine) + lftp per sincronitzar contingut des del FTP
# El repositori apt d'Angie no té paquets per a Ubuntu 24.04 (noble),
# així que fem servir la imatge Docker oficial directament.
FROM docker.angie.software/angie:latest

# Instal·lar eines de xarxa i lftp (Alpine usa apk)
RUN apk add --no-cache \
    iproute2 \
    iputils-ping \
    net-tools \
    curl \
    wget \
    ca-certificates \
    bind-tools \
    lftp \
    openssl \
    nano \
    bash

# Directoris de contingut
RUN mkdir -p /var/www/web03 && \
    chown -R angie:angie /var/www

# Pàgina per defecte (substituïda per setup-etapa6.sh)
RUN echo "<h1>web03 — Lab SFTPGo Etapa 6 (Angie)</h1>" > /var/www/web03/index.html

# Configuració bàsica per a web03 (sobreescrita per setup-etapa6.sh)
RUN printf 'server {\n\
    listen 80 default_server;\n\
    server_name web03.demoftp.test _;\n\
\n\
    root /var/www/web03;\n\
    index index.html;\n\
\n\
    location / {\n\
        try_files $uri $uri/ =404;\n\
    }\n\
\n\
    add_header X-Served-By "angie-web03" always;\n\
    add_header X-Lab-Stage "etapa6" always;\n\
    add_header X-Powered-By "Angie" always;\n\
}\n' > /etc/angie/http.d/web03.conf && \
    rm -f /etc/angie/http.d/default.conf

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# HTTP (Angie)
EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
