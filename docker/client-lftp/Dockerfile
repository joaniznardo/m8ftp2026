# ─── CLIENT-LFTP: client textual FTP amb lftp ────────────────────────────────
# Ubuntu 24.04 + lftp + eines de xarxa i diagnosi
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
    # Client FTP textual principal
    lftp \
    # Client FTP bàsic (referència)
    ftp \
    # TLS i certificats
    openssl \
    libnss3-tools \
    # Editors i utils
    nano \
    vim \
    bash \
    less \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Crear usuari ftpuser per al laboratori
RUN useradd -m -s /bin/bash ftpuser && \
    echo "ftpuser:ftppassword" | chpasswd

# Directoris de treball
RUN mkdir -p /home/ftpuser/downloads /home/ftpuser/uploads /home/ftpuser/certs && \
    chown -R ftpuser:ftpuser /home/ftpuser

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
