# ─── CLIENT-RCLONE: client FTP/S3 amb rclone ─────────────────────────────────
# Ubuntu 24.04 + rclone + lftp + eines de xarxa i diagnosi
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Madrid

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Xarxa i diagnosi
    iproute2 \
    iputils-ping \
    net-tools \
    tcpdump \
    curl \
    wget \
    ca-certificates \
    dnsutils \
    unzip \
    # lftp com a eina complementària
    lftp \
    ftp \
    # TLS i certificats
    openssl \
    # Editors i utils
    nano \
    vim \
    bash \
    less \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Instal·lar rclone des del repositori oficial (fallback al zip si el script falla)
# El fallback detecta l'arquitectura per suportar amd64 i arm64
RUN curl -sf https://rclone.org/install.sh | bash || \
    ( ARCH="$(dpkg --print-architecture)" && \
      curl -sfL "https://downloads.rclone.org/rclone-current-linux-${ARCH}.zip" \
           -o /tmp/rclone.zip && \
      unzip -o /tmp/rclone.zip -d /tmp/rclone-tmp && \
      cp /tmp/rclone-tmp/rclone-*/rclone /usr/local/bin/rclone && \
      chmod +x /usr/local/bin/rclone && \
      rm -rf /tmp/rclone.zip /tmp/rclone-tmp )

# Crear usuari ftpuser per al laboratori
RUN useradd -m -s /bin/bash ftpuser && \
    echo "ftpuser:ftppassword" | chpasswd

# Directoris de treball i config rclone
RUN mkdir -p /home/ftpuser/downloads /home/ftpuser/uploads \
             /home/ftpuser/certs /home/ftpuser/.config/rclone && \
    chown -R ftpuser:ftpuser /home/ftpuser

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
