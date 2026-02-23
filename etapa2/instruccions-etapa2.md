# Laboratori FTP amb SFTPGo — Etapa 2: FTPS/FTPES amb mkcert

## Objectiu

Habilitar el xifrat TLS al servidor FTP amb SFTPGo, usant certificats locals generats per **mkcert** per al domini `demoftp.test`. Es practica tant **FTPS implícit** (port 990) com **FTPES explícit** (port 21 + STARTTLS/AUTH TLS). Els certificats es distribueixen al client i al servidor.

---

## Prerequisits

- Etapa 1 completada (contenidors construïts i funcionant)
- `mkcert` instal·lat al **host** (no cal als contenidors, ja vénen amb la CA)

### Instal·lació de mkcert al host

```bash
# Linux (amd64)
curl -Lo /tmp/mkcert \
  https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64
chmod +x /tmp/mkcert
sudo mv /tmp/mkcert /usr/local/bin/mkcert

# Verificar
mkcert --version
```

---

## Pas 1: Generar els certificats per a demoftp.test

Executa l'script de configuració de l'etapa 2 des del directori arrel del lab:

```bash
bash configs/sftpgo/etapa2/setup-etapa2.sh
```

Alternativament, els passos manuals:

```bash
# Instal·lar la CA de mkcert al sistema
mkcert -install

# Obtenir el directori de la CA (per saber on és rootCA.pem)
mkcert -CAROOT

# Generar certificats per al domini i IPs del lab
cd certs/
mkcert \
  -cert-file demoftp.test.crt \
  -key-file  demoftp.test.key \
  demoftp.test \
  server.test \
  10.50.0.20 \
  localhost

# Copiar el certificat arrel
cp "$(mkcert -CAROOT)/rootCA.pem" ./
```

### Verificar els certificats

```bash
openssl x509 -in certs/demoftp.test.crt -noout -text | \
  grep -E "(Subject:|Issuer:|Not Before|Not After|DNS:|IP Address)"
```

Hauries de veure:
```
Subject: CN=demoftp.test
Issuer:  CN=mkcert joan@... (Local CA)
Not After: 2028-02-20...
DNS:demoftp.test, DNS:server.test, IP Address:10.50.0.20, IP Address:127.0.0.1
```

---

## Pas 2: Distribuir els certificats als contenidors

Els certificats a `certs/` es munten automàticament als contenidors via **bind mount** en la topologia containerlab:

- **Server:** `certs/` → `/etc/sftpgo/certs/`
- **Client:** `certs/` → `/home/ftpuser/certs/`

Si el lab ja estava en marxa, destrueix-lo i torna a desplegar-lo:

```bash
./lab.sh destroy
./lab.sh deploy 2
```

---

## Pas 3: Instal·lar la CA de mkcert als contenidors

La CA de mkcert ha de ser de confiança als contenidors per a que FileZilla accepte els certificats.

### Al servidor

```bash
docker exec -it clab-sftpgo-lab-server bash

# Instal·lar la CA de mkcert
cp /etc/sftpgo/certs/rootCA.pem /usr/local/share/ca-certificates/mkcert-lab.crt
update-ca-certificates

# Verificar
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt /etc/sftpgo/certs/demoftp.test.crt
```

### Al client

```bash
docker exec -it clab-sftpgo-lab-client bash

# Instal·lar la CA de mkcert
cp /home/ftpuser/certs/rootCA.pem /usr/local/share/ca-certificates/mkcert-lab.crt
update-ca-certificates
```

---

## Pas 4: Reconfigureció de SFTPGo per a FTPS/FTPES

### 4.1 Canviar la configuració activa al servidor

```bash
docker exec -it clab-sftpgo-lab-server bash

# Comprovar que els certificats existeixen
ls -la /etc/sftpgo/certs/

# Aturar SFTPGo
pkill sftpgo

# Arrancar amb la configuració de l'etapa 2
sftpgo serve --config-file /etc/sftpgo/etapa2/sftpgo.json &

# Verificar que escolta als ports correctes
ss -tlnp | grep -E ":(21|990|8080)"
```

Hauries de veure:
```
LISTEN   *:21    (FTPES - explícit)
LISTEN   *:990   (FTPS  - implícit)
LISTEN   *:8080  (Admin web HTTPS)
```

### 4.2 Verificar l'admin web amb TLS

```
https://localhost:8081/web/admin
```

> Si el navegador del host mostra "certificat no vàlid", instal·la la CA:
> ```bash
> # Ubuntu/Debian
> sudo cp certs/rootCA.pem /usr/local/share/ca-certificates/mkcert-lab.crt
> sudo update-ca-certificates
> ```

---

## Pas 5: Connectar amb FTPES (explícit TLS, port 21)

FTPES usa el protocol FTP estàndard al port 21, però afegeix xifrat TLS via la comanda `AUTH TLS`.

### 5.1 Configurar FileZilla (https://localhost:3001)

1. Obre FileZilla → **Gestor de llocs** (`Ctrl+S`)
2. Crea un nou lloc:
   - **Protocol:** FTP - Transferència de fitxers
   - **Host:** `demoftp.test`
   - **Port:** `21`
   - **Mode de xifratge:** Usa FTP sobre TLS explícit (FTPES)
   - **Tipus d'inici de sessió:** Normal
   - **Usuari:** `ftpuser`
   - **Contrasenya:** `ftppassword`
3. Fes clic a **Connecta**

> **Primer accés:** FileZilla mostrarà el certificat del servidor. Comprova que:
> - Emès per: `mkcert joan@...`
> - Per a: `demoftp.test`
> - Marca "Confiar en aquest certificat per a sessions futures"

### 5.2 Verificar via lftp (CLI)

```bash
docker exec -it clab-sftpgo-lab-client bash

lftp -e "set ftp:ssl-force true; set ssl:ca-file /home/ftpuser/certs/rootCA.pem" \
     -u ftpuser,ftppassword demoftp.test

lftp> debug 4          # Activar debug per veure el handshake TLS
lftp> ls               # Llistar fitxers
lftp> bye
```

---

## Pas 6: Connectar amb FTPS (implícit TLS, port 990)

FTPS implícit inicia **directament** una sessió TLS sense cap negociació prèvia en clar.

### 6.1 Configurar FileZilla

1. Gestor de llocs → nou lloc:
   - **Protocol:** FTP - Transferència de fitxers
   - **Host:** `demoftp.test`
   - **Port:** `990`
   - **Mode de xifratge:** Usa FTP sobre TLS implícit (FTPS)
   - **Usuari:** `ftpuser`
   - **Contrasenya:** `ftppassword`

### 6.2 Via lftp (CLI)

```bash
docker exec -it clab-sftpgo-lab-client bash

# FTPS implícit (ftps://)
lftp -e "set ssl:ca-file /home/ftpuser/certs/rootCA.pem" \
     ftps://ftpuser:ftppassword@demoftp.test:990

lftp> ls
lftp> bye
```

---

## Pas 7: Comparar el tràfic xifrat vs. no xifrat

### 7.1 Capturar el tràfic FTPES

```bash
docker exec -it clab-sftpgo-lab-client bash

# Captura del tràfic al port 21 (FTPES)
tcpdump -i eth1 -w /tmp/captura-ftpes.pcap port 21 or portrange 50000-50100 &
TCPDUMP_PID=$!

# Fes una connexió FTPES i transfereix un fitxer...
lftp -e "set ftp:ssl-force true; put /tmp/prova.txt; bye" \
     -u ftpuser,ftppassword demoftp.test

kill $TCPDUMP_PID

# Intenta llegir les credencials (no les veuràs!)
tcpdump -r /tmp/captura-ftpes.pcap -A | grep -E "USER|PASS" | head -20
```

### 7.2 Verificar el handshake TLS

```bash
# Veure el handshake TLS
openssl s_client -connect demoftp.test:21 -starttls ftp \
  -CAfile /etc/ssl/certs/ca-certificates.crt

# Per FTPS implícit (port 990)
openssl s_client -connect demoftp.test:990 \
  -CAfile /etc/ssl/certs/ca-certificates.crt
```

---

## Pas 8: Inspecció del certificat

### 8.1 Obtenir el certificat del servidor via OpenSSL

```bash
docker exec -it clab-sftpgo-lab-client bash

# Connexió FTPES i extracció del certificat
openssl s_client -connect demoftp.test:21 -starttls ftp \
  -CAfile /home/ftpuser/certs/rootCA.pem 2>/dev/null | \
  openssl x509 -noout -text
```

### 8.2 Validar la cadena de certificació

```bash
# Verificar que el certificat és vàlid amb la CA de mkcert
openssl verify \
  -CAfile /home/ftpuser/certs/rootCA.pem \
  /home/ftpuser/certs/demoftp.test.crt
```

Resultat esperat: `demoftp.test.crt: OK`

---

## Pas 9: Configuració dels ports passius FTPS

Els ports passius també han d'estar xifrats en FTPS/FTPES. Verifica la configuració:

```bash
docker exec -it clab-sftpgo-lab-server bash

# Verificar que els ports passius estan disponibles
ss -tlnp | grep -E ":(500[0-9]{2})"
```

Al `sftpgo.json` de l'etapa 2, el rang és `50000-50100`. Tots els canals de dades estaran xifrats.

---

## Pas 10: Accedir al Web Client de SFTPGo (HTTPS)

SFTPGo inclou un client web per als usuaris:

```
https://localhost:8081/web/client
```

- **Usuari:** `ftpuser`
- **Contrasenya:** `ftppassword`

Permet pujar i descarregar fitxers directament des del navegador.

---

## Resum de l'Etapa 2

| Aspecte | Etapa 1 | Etapa 2 |
|---------|---------|---------|
| Protocol | FTP (21) | FTPES (21) + FTPS (990) |
| Xifrat canal control | Cap | TLS 1.2+ |
| Xifrat canal dades | Cap | TLS 1.2+ |
| Certificats | No | mkcert (CA local) |
| Credencials en xarxa | Text pla | Xifrades |
| Admin web | HTTP | HTTPS |

---

## Preguntes de reflexió — Etapa 2

1. Quina diferència fonamental hi ha entre **FTPS implícit** (port 990) i **FTPES explícit** (port 21 + AUTH TLS)? Quin és recomanable per a nous desplegaments?
2. `mkcert` genera certificats signats per una **CA local**. Per quina raó no serien vàlids en Internet públic? Quan és apropiada una CA local?
3. Quan s'estableix una connexió FTPES, en quin moment exacte s'inicia el xifrat TLS? I en FTPS implícit?
4. Compara la captura de `tcpdump` de l'Etapa 1 (FTP) amb la de l'Etapa 2 (FTPES). Quines dades ja no pots llegir? Quines metadades segueixen sent visibles?
5. Quines dades conté un certificat X.509? Explica el paper de: `Subject`, `Issuer`, `SAN`, `Validity` i `Public Key`.
6. Si un atacant intercepta el tràfic FTPS, quina informació podria obtenir tot i el xifrat?
7. Quina versió mínima de TLS usa SFTPGo per defecte (`min_tls_version: 12`)? Per quina raó no s'haurien d'acceptar versions anteriors (TLS 1.0/1.1)?
8. Els ports passius `50000-50100` també estan xifrats en FTPS. Com es negocia el xifrat del canal de dades en mode passiu?
9. Si el certificat de `demoftp.test` no inclou la IP `10.50.0.20` als SANs, quin error rebràs? Com ho has verificat amb `openssl`?
10. Compara mkcert amb Let's Encrypt. Quins avantatges i limitacions té cadascun per a entorns de laboratori vs. producció?
