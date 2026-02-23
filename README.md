# Laboratori FTP/FTPS amb SFTPGo i Containerlab

Laboratori pràctic de 6 etapes progressives per aprendre el protocol FTP, xifrat
TLS, emmagatzematge S3, autenticació federada (OIDC), clients textuals i proxy
invers. Desplegat amb [Containerlab](https://containerlab.dev/) i
[SFTPGo](https://github.com/drakkan/sftpgo).

---

## Arquitectura general

```
Host Linux
  |
  +-- https://localhost:3001  --> FileZilla GUI (Selkies/WebRTC)
  +-- http(s)://localhost:8081 --> SFTPGo Web Admin
  
  Xarxa LAN: 10.50.0.0/24
  +-------------------------------------------------+
  |  [switch-lan]              Linux bridge          |
  |  [router-frr]  10.50.0.1   FRR (gateway LAN)    |
  |  [coredns]     10.50.0.53  DNS (demoftp.test)    |
  |  [server]      10.50.0.20  SFTPGo FTP            |
  |  [client]      10.50.0.10  FileZilla (WebRTC)    |
  +-------------------------------------------------+
```

Cada etapa afegeix nous nodes i funcionalitats sobre aquesta base.

---

## Prerequisits

| Eina | Versio minima | Instal·lacio |
|------|---------------|--------------|
| Docker | 20+ | `apt install docker.io` |
| Containerlab | 0.44+ | `sudo bash -c "$(curl -sL https://get.containerlab.dev)"` |
| mkcert | 1.4+ | `apt install mkcert` (necessari per a etapes 2+) |

Verificacio rapida:

```bash
./lab.sh check
```

---

## Referencia rapida de comandes

```bash
./lab.sh check              # Comprova prerequisits
./lab.sh build              # Construeix totes les imatges custom
./lab.sh build switch       # Construeix nomes la imatge del switch
./lab.sh certs              # Genera certificats TLS amb mkcert (etapa 2+)
./lab.sh deploy <N>         # Desplega l'etapa N (1-6)
./lab.sh setup <N>          # Executa la configuracio addicional (etapes 3-6)
./lab.sh status             # Mostra l'estat del lab
./lab.sh shell <node>       # Obre shell a un node (default: client)
./lab.sh logs <node>        # Mostra logs d'un node (default: server)
./lab.sh destroy            # Destrueix el lab actual
```

---

## Credencials

| Servei | Usuari | Contrasenya |
|--------|--------|-------------|
| FTP (SFTPGo) | `ftpuser` | `ftppassword` |
| SFTPGo admin | `admin` | `admin` |
| FileZilla GUI (WebRTC) | — | `labvnc` |
| MinIO (etapa 3) | `rustfs-access-key` | `rustfs-secret-key` |
| Keycloak (etapa 4) | `admin` | `admin` |

---

## Etapa 1 — FTP sense xifrat

**Objectiu:** Desplegar un servidor FTP funcional i observar que el trafic
(usuari, contrasenya, dades) viatja en text pla.

**Nodes:** 5 (switch, router, coredns, server, client)

### Pas a pas

```bash
# 1. Construir la imatge del switch (unica imatge custom)
./lab.sh build switch

# 2. Desplegar
./lab.sh deploy 1

# 3. Verificar que els 5 nodes estan actius
./lab.sh status
```

### Verificacio

```bash
# Accedir al client FileZilla via navegador
#   https://localhost:3001   (contrasenya: labvnc)

# Accedir al panell d'admin de SFTPGo
#   http://localhost:8081/web/admin   (admin / admin)

# L'usuari ftpuser es crea automaticament via l'API REST.
# Verificar des del servidor:
./lab.sh shell server
ss -tlnp | grep :21
```

### Connexio FTP des de FileZilla

1. Obre FileZilla (https://localhost:3001) → Gestor de llocs (`Ctrl+S`)
2. Crea un nou lloc:
   - **Host:** `demoftp.test` | **Port:** `21`
   - **Xifratge:** Usa FTP en text clar (No TLS)
   - **Usuari:** `ftpuser` | **Contrasenya:** `ftppassword`
3. Connecta

### Connexio FTP des de la linia de comandes

```bash
./lab.sh shell client

# Llistar fitxers
curl -v ftp://ftpuser:ftppassword@demoftp.test/

# Pujar un fitxer
curl -s ftp://ftpuser:ftppassword@demoftp.test/ -T /etc/hostname

# Descarregar un fitxer
curl -o /tmp/descarregat.txt ftp://ftpuser:ftppassword@demoftp.test/hostname
```

### Captura de trafic (demostrar la inseguretat)

```bash
./lab.sh shell client

# Capturar trafic FTP
tcpdump -i eth1 -w /tmp/captura-ftp.pcap port 21 &

# Fer una connexio FTP (des d'una altra terminal)
curl -s ftp://ftpuser:ftppassword@demoftp.test/ > /dev/null

# Aturar la captura i llegir
kill %1
tcpdump -r /tmp/captura-ftp.pcap -A | grep -E "USER|PASS"
# Resultat: USER ftpuser / PASS ftppassword  (en clar!)
```

### Aturar

```bash
./lab.sh destroy
```

---

## Etapa 2 — FTPES i FTPS amb mkcert

**Objectiu:** Habilitar xifrat TLS al servidor FTP: FTPES (explicit TLS, port 21)
i FTPS (implicit TLS, port 990). Generar certificats amb mkcert.

**Nodes:** 5 (mateixos que l'etapa 1)

### Pas a pas

```bash
# 1. Generar certificats TLS
./lab.sh certs

# 2. Desplegar
./lab.sh deploy 2

# 3. Verificar
./lab.sh status
```

### Verificacio dels certificats

```bash
# Comprovar el certificat generat
openssl x509 -in certs/demoftp.test.crt -noout -text | \
  grep -E "(Subject:|Issuer:|DNS:|IP Address)"
```

### Instal·lar la CA als contenidors

```bash
# Al servidor
docker exec clab-sftpgo-lab-server bash -c "
    cp /etc/sftpgo/certs/rootCA.pem /usr/local/share/ca-certificates/mkcert-lab.crt
    update-ca-certificates
"

# Al client
docker exec clab-sftpgo-lab-client bash -c "
    cp /home/ftpuser/certs/rootCA.pem /usr/local/share/ca-certificates/mkcert-lab.crt
    update-ca-certificates
"
```

### Connexio FTPES (TLS explicit, port 21)

Des de FileZilla:
1. Gestor de llocs → Nou lloc
2. **Host:** `demoftp.test` | **Port:** `21`
3. **Xifratge:** Usa FTP sobre TLS explicit (FTPES)
4. **Usuari:** `ftpuser` | **Contrasenya:** `ftppassword`

Des de la linia de comandes:
```bash
./lab.sh shell client

# Verificar el handshake TLS
openssl s_client -connect demoftp.test:21 -starttls ftp \
  -CAfile /home/ftpuser/certs/rootCA.pem
```

### Connexio FTPS (TLS implicit, port 990)

Des de FileZilla:
1. **Host:** `demoftp.test` | **Port:** `990`
2. **Xifratge:** Usa FTP sobre TLS implicit (FTPS)

Des de la linia de comandes:
```bash
# FTPS implicit (port 990)
openssl s_client -connect demoftp.test:990 \
  -CAfile /home/ftpuser/certs/rootCA.pem
```

### Comparar trafic xifrat vs. text pla

```bash
./lab.sh shell client

# Capturar trafic FTPES
tcpdump -i eth1 -w /tmp/captura-ftpes.pcap port 21 &

# Connexio FTPES
lftp -e "set ftp:ssl-force true; set ssl:ca-file /home/ftpuser/certs/rootCA.pem; ls; bye" \
     -u ftpuser,ftppassword demoftp.test

kill %1
tcpdump -r /tmp/captura-ftpes.pcap -A | grep -E "USER|PASS"
# Resultat: res! Les credencials estan xifrades
```

### Aturar

```bash
./lab.sh destroy
```

---

## Etapa 3 — Emmagatzematge S3 amb MinIO

**Objectiu:** Configurar SFTPGo perque guardi els fitxers en un bucket S3
(MinIO) en lloc del disc local. El servidor FTP es torna *stateless*.

**Nodes:** 6 (base + rustfs/MinIO a 10.50.0.30)

### Pas a pas

```bash
# 1. Generar certificats (si no s'ha fet)
./lab.sh certs

# 2. Desplegar
./lab.sh deploy 3

# 3. Verificar els 6 nodes
./lab.sh status

# 4. Executar el script de configuracio
#    - Crea el bucket sftpgo-data a MinIO
#    - Configura SFTPGo per usar el backend S3
./lab.sh setup 3
```

### Verificacio

```bash
# Consola web de MinIO
#   http://localhost:9001   (rustfs-access-key / rustfs-secret-key)

# Admin SFTPGo
#   https://localhost:8081/web/admin   (admin / admin)

# Verificar DNS
docker exec clab-sftpgo-lab-client dig rustfs.test @10.50.0.53

# Connexio FTPES i llistat
docker exec clab-sftpgo-lab-client \
  curl -k --ftp-ssl ftp://ftpuser:ftppassword@demoftp.test/
```

### Crear un usuari FTP amb backend S3 (via admin web)

1. Obre https://localhost:8081/web/admin → Users → Add User
2. **Username:** `ftpuser`
3. Seccio **Filesystem**:
   - **Storage:** S3 Compatible
   - **Endpoint:** `http://rustfs.test:9000`
   - **Bucket:** `sftpgo-data`
   - **Access Key:** `rustfs-access-key`
   - **Access Secret:** `rustfs-secret-key`
   - **Key Prefix:** `ftpuser/`
4. Desa

### Verificar que els fitxers van al bucket

```bash
# Pujar un fitxer via FTP
docker exec clab-sftpgo-lab-client bash -c "
    echo 'prova S3' > /tmp/prova.txt
    curl -k --ftp-ssl ftp://ftpuser:ftppassword@demoftp.test/ -T /tmp/prova.txt
"

# Verificar al bucket via mc (MinIO Client)
docker exec clab-sftpgo-lab-rustfs mc ls local/sftpgo-data/ftpuser/
```

### Aturar

```bash
./lab.sh destroy
```

---

## Etapa 4 — Autenticacio federada amb Keycloak (OIDC)

**Objectiu:** Integrar Keycloak com a proveidor d'identitat OpenID Connect.
Els usuaris FTP s'autentiquen contra Keycloak en lloc de la base de dades
local de SFTPGo.

**Nodes:** 6 (base + keycloak a 10.50.0.40)

### Pas a pas

```bash
# 1. Generar certificats (si no s'ha fet)
./lab.sh certs

# 2. Desplegar
./lab.sh deploy 4

# 3. Verificar els 6 nodes
./lab.sh status

# 4. Executar el script de configuracio
#    - Crea el realm "lab" a Keycloak
#    - Crea el client "sftpgo" (confidential, Direct Access Grants)
#    - Crea l'usuari ftpuser amb contrasenya ftppassword
#    - Genera el hook d'autenticacio a /usr/local/bin/auth-keycloak.sh
./lab.sh setup 4
```

### Verificacio

```bash
# Consola web de Keycloak
#   http://localhost:8180/admin   (admin / admin)

# Verificar que el realm "lab" existeix
curl -s http://localhost:8180/realms/lab | jq .realm

# Obtenir un token OIDC (prova directa)
curl -s -X POST \
  "http://localhost:8180/realms/lab/protocol/openid-connect/token" \
  -d "client_id=sftpgo" \
  -d "client_secret=$(curl -s http://localhost:8180/admin/realms/lab/clients?clientId=sftpgo \
      -H "Authorization: Bearer $(curl -s http://localhost:8180/realms/master/protocol/openid-connect/token \
      -d client_id=admin-cli -d grant_type=password -d username=admin -d password=admin | jq -r .access_token)" \
      | jq -r '.[0].secret')" \
  -d "grant_type=password" \
  -d "username=ftpuser" \
  -d "password=ftppassword" | jq .access_token
```

### Connexio FTP via Keycloak

```bash
# Des del client FileZilla (https://localhost:3001):
#   Host: demoftp.test | Port: 21 | FTPES
#   Usuari: ftpuser | Contrasenya: ftppassword
#
# SFTPGo crida el hook → el hook valida contra Keycloak → connexio acceptada.

# Provar credencials incorrectes per verificar que Keycloak rebutja:
docker exec clab-sftpgo-lab-client \
  curl -k --ftp-ssl ftp://ftpuser:MAL@demoftp.test/ 2>&1 | grep -i "login"
```

### Inspeccionar un token JWT

```bash
# Decodificar el payload del token
TOKEN="$(curl -s -X POST http://localhost:8180/realms/lab/protocol/openid-connect/token \
  -d client_id=sftpgo -d grant_type=password \
  -d username=ftpuser -d password=ftppassword \
  -d "client_secret=..." | jq -r .access_token)"

echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq .
# Camps rellevants: sub, iss, exp, preferred_username
```

### Aturar

```bash
./lab.sh destroy
```

---

## Etapa 5 — Clients textuals (lftp i rclone)

**Objectiu:** Usar clients FTP de linia de comandes per a automatitzacio
i transferencies sense interficie grafica.

**Nodes:** 7 (base + client-lftp a 10.50.0.11 + client-rclone a 10.50.0.12)

### Pas a pas

```bash
# 1. Construir les imatges custom dels clients
./lab.sh build client-lftp
./lab.sh build client-rclone

# 2. Generar certificats (si no s'ha fet)
./lab.sh certs

# 3. Desplegar
./lab.sh deploy 5

# 4. Verificar els 7 nodes
./lab.sh status

# 5. Executar el script de configuracio
#    - Configura ~/.lftp/rc amb TLS activat
#    - Crea ~/.config/rclone/rclone.conf amb connexio FTPES
#    - Genera scripts de demo
./lab.sh setup 5
```

### Us de lftp (mode interactiu)

```bash
./lab.sh shell client-lftp

# Connexio FTPES
lftp -u ftpuser,ftppassword demoftp.test

# Dins de lftp:
lftp> ls
lftp> mkdir proves
lftp> put /etc/hostname -o proves/hostname.txt
lftp> get proves/hostname.txt -o /tmp/descarregat.txt
lftp> mirror / /tmp/mirall/
lftp> bye
```

### Us de lftp (mode script / automatitzacio)

```bash
# Llistar
lftp -u ftpuser,ftppassword demoftp.test -e "ls; bye"

# Pujar
echo "contingut" > /tmp/test.txt
lftp -u ftpuser,ftppassword demoftp.test -e "put /tmp/test.txt; bye"

# Mirror (sincronitzar remot → local)
lftp -u ftpuser,ftppassword demoftp.test -e "mirror / /tmp/mirall/; bye"

# Mirror invers (local → remot)
lftp -u ftpuser,ftppassword demoftp.test -e "mirror -R /tmp/dades/ /backup/; bye"
```

### Us de rclone

```bash
./lab.sh shell client-rclone

# Verificar configuracio
rclone config show

# Llistar
rclone ls demoftp:

# Copiar local → remot
echo "hola" > /tmp/test-rclone.txt
rclone copy /tmp/test-rclone.txt demoftp:proves/

# Copiar remot → local
rclone copy demoftp:proves/ /tmp/descarrega/

# Sincronitzar (esborra fitxers a destinacio no presents a origen)
rclone sync /tmp/dades/ demoftp:backup/
```

### Executar les demos preparades

```bash
# Demo lftp
docker exec clab-sftpgo-lab-client-lftp bash /home/ftpuser/demo-lftp.sh

# Demo rclone
docker exec clab-sftpgo-lab-client-rclone bash /home/ftpuser/demo-rclone.sh
```

### Aturar

```bash
./lab.sh destroy
```

---

## Etapa 6 — Proxy invers (nginx + Angie)

**Objectiu:** Servir tres llocs web (`web01`, `web02`, `web03.demoftp.test`)
a traves d'un proxy invers nginx, on el contingut de cada web prové d'un
directori del servidor FTP (SFTPGo). `web01` i `web02` usen nginx; `web03`
usa Angie (fork modern de nginx).

**Nodes:** 9 (base + proxy a 10.50.0.60 + web01 a 10.50.0.61 + web02 a
10.50.0.62 + web03 a 10.50.0.63)

### Pas a pas

```bash
# 1. Construir les imatges custom
./lab.sh build proxy
./lab.sh build web-nginx
./lab.sh build web-angie

# 2. Generar certificats (si no s'ha fet)
./lab.sh certs

# 3. Desplegar
./lab.sh deploy 6

# 4. Verificar els 9 nodes
./lab.sh status

# 5. Executar el script de configuracio
#    - Crea contingut HTML a /web01/, /web02/, /web03/ al servidor FTP
#    - Sincronitza contingut via lftp als servidors web
#    - Configura nginx/angie als servidors web
#    - Configura el proxy invers amb 3 vhosts
./lab.sh setup 6
```

### Verificacio des del host

```bash
# Cada vhost respon a traves del proxy (port 8091)
curl -H 'Host: web01.demoftp.test' http://localhost:8091/
curl -H 'Host: web02.demoftp.test' http://localhost:8091/
curl -H 'Host: web03.demoftp.test' http://localhost:8091/

# Comprovar capcaleres
curl -sI -H 'Host: web01.demoftp.test' http://localhost:8091/ | grep X-
# X-Served-By: nginx-web01
# X-Lab-Stage: etapa6
# X-Proxy: nginx-proxy

curl -sI -H 'Host: web03.demoftp.test' http://localhost:8091/ | grep X-
# X-Served-By: angie-web03
# X-Powered-By: Angie
# X-Proxy: nginx-proxy
```

### Navegacio directa des del navegador

```bash
# Afegir al /etc/hosts del host
echo "127.0.0.1  web01.demoftp.test web02.demoftp.test web03.demoftp.test" \
    | sudo tee -a /etc/hosts

# Obrir al navegador:
#   http://web01.demoftp.test:8091
#   http://web02.demoftp.test:8091
#   http://web03.demoftp.test:8091
```

### Actualitzar contingut web via FTP

```bash
# 1. Pujar nou contingut al servidor FTP
docker exec clab-sftpgo-lab-client lftp -u ftpuser,ftppassword demoftp.test -e "
    put /tmp/nou-index.html -o /web01/index.html
    bye
"

# 2. Sincronitzar el contingut als servidors web
docker exec clab-sftpgo-lab-web01 lftp -u ftpuser,ftppassword demoftp.test -e "
    set ftp:passive-mode yes
    mirror /web01/ /var/www/web01/
    bye
"

# 3. Verificar
curl -H 'Host: web01.demoftp.test' http://localhost:8091/
```

### Diagnosi

```bash
# Logs del proxy
docker exec clab-sftpgo-lab-proxy tail -f /var/log/nginx/access.log

# Logs d'Angie (web03)
docker exec clab-sftpgo-lab-web03 tail -f /var/log/angie/access.log

# Verificar configuracio
docker exec clab-sftpgo-lab-proxy nginx -t
docker exec clab-sftpgo-lab-web03 angie -t
```

### Aturar

```bash
./lab.sh destroy
```

---

## Resum de les 6 etapes

| Etapa | Tema | Nodes | Ports host | Protocol |
|-------|------|-------|------------|----------|
| 1 | FTP sense xifrat | 5 | 3001, 8081 | FTP (21) |
| 2 | FTPES + FTPS | 5 | 3001, 8081 | FTPES (21), FTPS (990) |
| 3 | Backend S3 | 6 | 3001, 8081, 9001 | FTPES + S3 API |
| 4 | Auth OIDC | 6 | 3001, 8081, 8180 | FTPES + OAuth2 |
| 5 | Clients CLI | 7 | 3001, 8081 | FTPES (lftp, rclone) |
| 6 | Proxy invers | 9 | 3001, 8081, 8091 | FTPES + HTTP proxy |

---

## Estructura del repositori

```
lab.sh                      # Script principal de gestio
topologies/
  etapa{1..6}.yml           # Topologia per etapa
configs/
  sftpgo/etapa{1..6}/       # sftpgo.json + scripts de setup (etapes 3-6)
  coredns/                  # Corefile + zones DNS
  frr/                      # Configuracio FRR (router)
  switch/                   # init-bridge.sh
scripts/
  server-init.sh            # Xarxa + creacio ftpuser via API
  client-init.sh            # Xarxa del client FileZilla
  router-init.sh            # Xarxa del router FRR
  init-client-lftp.sh       # Xarxa del client lftp (etapa 5)
  init-client-rclone.sh     # Xarxa del client rclone (etapa 5)
  init-proxy.sh             # Xarxa + nginx del proxy (etapa 6)
  init-web-nginx.sh         # Xarxa + nginx de web01/web02 (etapa 6)
  init-web-angie.sh         # Xarxa + angie de web03 (etapa 6)
docker/
  switch/                   # Imatge custom: Linux bridge (Ubuntu 24.04)
  client-lftp/              # Imatge custom: lftp (etapa 5)
  client-rclone/            # Imatge custom: rclone (etapa 5)
  proxy/                    # Imatge custom: nginx proxy (etapa 6)
  web-nginx/                # Imatge custom: nginx web (etapa 6)
  web-angie/                # Imatge custom: Angie web (etapa 6)
certs/                      # Certificats TLS (generats per ./lab.sh certs)
etapa{1..6}/                # Instruccions detallades per etapa
presentation/               # Presentacio reveal.js
```

---

## Imatges Docker

| Node | Imatge | Tipus |
|------|--------|-------|
| server | `drakkan/sftpgo:latest` | Oficial |
| client | `lscr.io/linuxserver/filezilla:latest` | Oficial |
| router-frr | `frrouting/frr:latest` | Oficial |
| coredns | `coredns/coredns:latest` | Oficial |
| switch-lan | `sftpgo-lab/switch:latest` | Custom |
| client-lftp | `sftpgo-lab/client-lftp:latest` | Custom (etapa 5) |
| client-rclone | `sftpgo-lab/client-rclone:latest` | Custom (etapa 5) |
| proxy | `sftpgo-lab/proxy:latest` | Custom (etapa 6) |
| web01, web02 | `sftpgo-lab/web-nginx:latest` | Custom (etapa 6) |
| web03 | `sftpgo-lab/web-angie:latest` | Custom (etapa 6) |

---

## Xarxa

| Node | IP | Funcio |
|------|----|--------|
| router-frr | 10.50.0.1 | Gateway LAN |
| client | 10.50.0.10 | FileZilla GUI |
| client-lftp | 10.50.0.11 | lftp CLI (etapa 5) |
| client-rclone | 10.50.0.12 | rclone CLI (etapa 5) |
| server | 10.50.0.20 | SFTPGo FTP |
| rustfs | 10.50.0.30 | MinIO S3 (etapa 3) |
| keycloak | 10.50.0.40 | Keycloak IdP (etapa 4) |
| coredns | 10.50.0.53 | DNS |
| proxy | 10.50.0.60 | Proxy invers (etapa 6) |
| web01 | 10.50.0.61 | nginx web (etapa 6) |
| web02 | 10.50.0.62 | nginx web (etapa 6) |
| web03 | 10.50.0.63 | Angie web (etapa 6) |

**Domini:** `demoftp.test` resol a 10.50.0.20

---

## Llicencia

Material didactic de l'Institut TIC de Barcelona.
