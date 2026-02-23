# Laboratori FTP amb SFTPGo — Etapa 5: Clients textuals i online

## Objectiu

Explorar **clients FTP textuals** (`lftp`, `rclone`) i identificar **clients FTP online segurs** per accedir al servidor SFTPGo. Aprendrem les diferències entre clients gràfics i de línia de comandes, la configuració FTPES/FTPS en mode text, i l'automatització de transferències sense interfície gràfica.

---

## Arquitectura de la xarxa

```
Host Linux (tu)
  │
  ├─ https://localhost:3001  → WebRTC / Selkies (FileZilla GUI) — client original
  ├─ https://localhost:8081 → SFTPGo Web Admin

  Xarxa LAN: 10.50.0.0/24
  ┌───────────────────────────────────────────────────────────────────┐
  │  [client]         10.50.0.10  FileZilla + WebRTC / Selkies (GUI)    │
  │  [client-lftp]    10.50.0.11  lftp (client textual)    ← NOU    │
  │  [client-rclone]  10.50.0.12  rclone (client modern)   ← NOU    │
  │  [server]         10.50.0.20  SFTPGo (FTPES port 21)            │
  │  [coredns]        10.50.0.53  DNS                               │
  │  [router]         10.50.0.1   FRR (gateway LAN)                 │
  │  [switch]                     Linux bridge                       │
  └───────────────────────────────────────────────────────────────────┘

  Flux de connexions:
    client-lftp    → FTPES (TLS explícit, port 21) → server SFTPGo
    client-rclone  → FTPES (TLS explícit, port 21) → server SFTPGo
```

---

## Prerequisits

- Etapes 1 i 2 completades (SFTPGo funcional + certificats mkcert)
- Imatges Docker construïdes: `sftpgo-lab/client-lftp` i `sftpgo-lab/client-rclone`
- Nodes `client-lftp` i `client-rclone` inclosos a `topologies/etapa5.yml`

---

## Pas 1: Activar els nodes clients a la topologia

La topologia `topologies/etapa5.yml` ja inclou els nodes `client-lftp` i `client-rclone` amb tota la configuració necessària (IPs, links, binds i scripts d'inicialització). No cal editar ni descomentar res manualment.

Els registres DNS corresponents també ja estan configurats a les zones de CoreDNS.

Per desplegar el laboratori d'aquesta etapa:

```bash
./lab.sh deploy 5
```

---

## Pas 2: Construir les imatges i redesplegar

```bash
# Construir totes les imatges (inclou les noves)
./lab.sh build

# Destruir i redesplegar
./lab.sh destroy
./lab.sh deploy 5
```

---

## Pas 3: Executar el script de configuració

```bash
./lab.sh setup5
```

El script `setup-etapa5.sh`:
- Configura `~/.lftp/rc` al node `client-lftp` amb TLS activat
- Crea `~/.config/rclone/rclone.conf` al node `client-rclone` amb la connexió FTPES
- Genera scripts de demo (`demo-lftp.sh`, `demo-rclone.sh`) en cada node

---

## Pas 4: Ús de lftp (mode interactiu)

```bash
# Entrar al contenidor client-lftp
./lab.sh shell client-lftp

# Connexió interactiva FTPES (TLS explícit)
lftp -u ftpuser,ftppassword demoftp.test

# Dins de lftp:
lftp ftpuser@demoftp.test:~> ls
lftp ftpuser@demoftp.test:~> mkdir proves
lftp ftpuser@demoftp.test:~> put /etc/hostname -o proves/hostname.txt
lftp ftpuser@demoftp.test:~> get proves/hostname.txt -o /tmp/descarregat.txt
lftp ftpuser@demoftp.test:~> mirror / /tmp/mirall/    # descarrega tot
lftp ftpuser@demoftp.test:~> bye
```

---

## Pas 5: Ús de lftp (mode no-interactiu / scripts)

```bash
# Llistar el directori remot (una línia)
lftp -u ftpuser,ftppassword demoftp.test -e "ls; bye"

# Pujar un fitxer
echo "contingut de prova" > /tmp/test.txt
lftp -u ftpuser,ftppassword demoftp.test -e "put /tmp/test.txt; bye"

# Descarregar un fitxer
lftp -u ftpuser,ftppassword demoftp.test -e "get test.txt -o /tmp/test-descarregat.txt; bye"

# Mirror (sincronitza directori remot → local)
lftp -u ftpuser,ftppassword demoftp.test -e "mirror / /tmp/mirall/; bye"

# Mirror invers (sincronitza local → remot)
lftp -u ftpuser,ftppassword demoftp.test -e "mirror -R /tmp/dades/ /backup/; bye"

# Executar la demo preparada pel setup
bash /home/ftpuser/demo-lftp.sh
```

---

## Pas 6: Configuració lftp (fitxer ~/.lftp/rc)

El script de setup crea la configuració TLS automàticament. Revisa-la:

```bash
cat ~/.lftp/rc
```

Contingut típic:
```
# ~/.lftp/rc — Configuració per al lab
set ftp:ssl-allow yes
set ftp:ssl-force yes           # Forçar TLS (FTPES)
set ftp:ssl-protect-data yes    # Xifrar canal de dades
set ftp:ssl-protect-list yes    # Xifrar llistat de directori
set ssl:verify-certificate yes  # Verificar certificat
set ssl:ca-file /home/ftpuser/certs/rootCA.pem
set ftp:passive-mode yes        # Mode passiu
```

---

## Pas 7: Ús de rclone

```bash
# Entrar al contenidor client-rclone
./lab.sh shell client-rclone

# Verificar la configuració
rclone config show

# Llistar el remot FTP
rclone ls demoftp:

# Copiar un fitxer local → remot
echo "hola" > /tmp/test-rclone.txt
rclone copy /tmp/test-rclone.txt demoftp:proves/

# Copiar remot → local
mkdir -p /tmp/descàrrega
rclone copy demoftp:proves/ /tmp/descàrrega/

# Sincronitzar (sync: esborrarà fitxers a destinació no presents a origen)
rclone sync /tmp/dades/ demoftp:backup/

# Llistar tots els fitxers recursivament
rclone ls demoftp:

# Verificar espai (si SFTPGo reporta quota)
rclone about demoftp:

# Executar la demo preparada
bash /home/ftpuser/demo-rclone.sh
```

---

## Pas 8: Configuració rclone (fitxer rclone.conf)

```bash
cat ~/.config/rclone/rclone.conf
```

Contingut:
```ini
[demoftp]
type = ftp
host = demoftp.test
port = 21
user = ftpuser
pass = <contrasenya ofuscada per rclone>
tls = false           # FTPS implícit → false
explicit_tls = true   # FTPES (TLS explícit) → true
no_check_certificate = false
concurrency = 4
```

---

## Pas 9: Clients FTP online segurs recomanats

Per accedir al servidor des del navegador (sense instal·lar res), existeixen clients FTP online segurs:

### Filestash (recomanat, self-hosted)

**URL:** https://www.filestash.app

| Característica | Detall |
|----------------|--------|
| Protocol suportat | FTPES (TLS explícit), FTPS, SFTP, S3, etc. |
| Seguretat | Connexió des del navegador del client |
| Desplegament | Self-hosted (Docker) o servei en línia |
| Privacitat | Credencials mai emmagatzemades al servidor |

Connexió des de filestash:
- **Protocol:** FTP
- **Host:** `demoftp.test` (o la IP pública si el lab és accessible externament)
- **Port:** 21
- **TLS:** Explícit (FTPES)
- **Usuari:** `ftpuser`
- **Contrasenya:** `ftppassword`

### net2ftp (alternatiu)

**URL:** https://www.net2ftp.com

| Característica | Detall |
|----------------|--------|
| Protocol suportat | FTP/FTPS des del servidor net2ftp cap al teu servidor |
| Seguretat | Connexió va pels servidors de net2ftp |
| Ús | Navegació web sense instal·lació |

> **Nota de seguretat:** Amb net2ftp, les credencials passen pels servidors de net2ftp abans d'arribar al teu servidor. Només recomanat per a labs on el servidor FTP és accessible públicament i amb credencials de prova. Per a producció, usar **Filestash self-hosted**.

---

## Pas 10: Verificació de connectivitat i diagnosi

```bash
# DNS des del client-lftp
docker exec clab-sftpgo-lab-client-lftp dig demoftp.test @10.50.0.53

# Ping
docker exec clab-sftpgo-lab-client-lftp ping -c 3 demoftp.test

# Verificar TLS (handshake FTPES)
docker exec clab-sftpgo-lab-client-lftp \
  openssl s_client -connect demoftp.test:21 -starttls ftp \
    -CAfile /home/ftpuser/certs/rootCA.pem

# Verificar que el port 21 escolta al servidor
docker exec clab-sftpgo-lab-server ss -tlnp | grep :21

# Llistat ràpid via lftp sense entrar al contenidor
docker exec clab-sftpgo-lab-client-lftp \
  lftp -u ftpuser,ftppassword demoftp.test -e "ls; bye"

# Llistat via rclone sense entrar al contenidor
docker exec clab-sftpgo-lab-client-rclone \
  rclone ls demoftp:
```

---

## Taula resum: comparativa de clients

| Client | Protocol | TLS | Mode | Instal·lació | Cas d'ús |
|--------|----------|-----|------|--------------|----------|
| FileZilla | FTP/FTPES/FTPS | Sí | GUI | Sí (app) | Ús diari, interfície gràfica |
| lftp | FTP/FTPES/FTPS | Sí | CLI | Sí (apt) | Scripts, automatització, servidors |
| rclone | FTP/FTPES/S3/SFTP | Sí | CLI | Sí (binari) | Sincronització, cloud, multi-backend |
| Filestash | FTP/FTPES/SFTP | Sí | Web | Docker/SaaS | Accés web sense instal·lació |
| net2ftp | FTP/FTPS | Parcial | Web | No | Accés puntual, labs |

---

## Preguntes de reflexió

1. **Quina diferència fonamental hi ha entre mode interactiu i no-interactiu d'lftp?** Posa un exemple de cas on cada un és més adequat.

2. **Quan lftp usa `set ftp:ssl-force yes`, en quin moment del protocol s'envia la comanda `AUTH TLS`?** Quin és l'efecte si el servidor no la suporta?

3. **Per què rclone "ofusca" la contrasenya al fitxer de configuració en lloc d'emmagatzemar-la en text pla?** Garanteix seguretat real o és simplement ofuscació?

4. **Compara `mirror` d'lftp amb `sync` de rclone.** Quines opcions ofereix cada un per evitar esborrats accidentals?

5. **Filestash actua com a proxy entre el navegador i el servidor FTP.** En quin punt exacte s'estableix la connexió TLS? Des del navegador fins a Filestash, o des de Filestash fins al servidor FTP?

6. **Quines implicacions de seguretat té usar un client FTP online de tercers (net2ftp) amb credencials reals?** Descriu el flux de credencials.

7. **lftp pot fer transferències en paral·lel (`pget -n 4`).** Com afecta això al rang de ports passius configurats a SFTPGo (50000-50100)?

8. **rclone suporta múltiples backends (FTP, S3, SFTP, Google Drive...).** Quins avantatges té per a un administrador de sistemes respecte a tenir un client diferent per a cada protocol?

9. **Quin dels dos clients (lftp o rclone) té millor suport per a reprendre transferències interrompudes (`resume`)?** Com es configura?

10. **En un entorn de producció, si cal automatitzar còpies de seguretat FTP nocturnes, quin client recomanaries i per què?** Escriu l'exemple de comanda que usaries en un cron job.
