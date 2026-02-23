# Laboratori FTP amb SFTPGo — Etapa 1: FTP sense xifrat

## Objectiu

Desplegar un servidor FTP funcional amb SFTPGo en un entorn de xarxa virtualitzat amb Containerlab, accedint-hi des d'un client FileZilla, **sense cap capa de xifrat**. Això permet observar el tràfic en clar i comprendre els riscos del protocol FTP tradicional.

---

## Arquitectura de la xarxa

```
Host Linux (tu)
  |
  +-- https://localhost:3001  --> FileZilla GUI (Selkies/WebRTC)
  +-- http://localhost:8081   --> SFTPGo Web Admin
  
  Xarxa LAN: 10.50.0.0/24
  +-----------------------------------------------+
  |  [client]      10.50.0.10  FileZilla (WebRTC)  |
  |  [server]      10.50.0.20  SFTPGo FTP          |
  |  [coredns]     10.50.0.53  DNS (demoftp.test)  |
  |  [router-frr]  10.50.0.1   FRR (gateway LAN)   |
  |  [switch-lan]              Linux bridge         |
  +-----------------------------------------------+
```

**Domini:** `demoftp.test` --> 10.50.0.20

---

## Prerequisits

### Al host Linux

```bash
# 1. Docker instal·lat i funcionant
docker version

# 2. Containerlab instal·lat
sudo bash -c "$(curl -sL https://get.containerlab.dev)"

# 3. Clonar / situar-se al directori del lab
cd 006-sftpgo-lab/

# 4. Comprovar prerequisits automàticament
./lab.sh check
```

---

## Pas 1: Construir la imatge Docker del switch

L'unica imatge personalitzada que cal construir es la del switch (Linux bridge).
La resta de nodes utilitzen imatges oficials de Docker Hub:

- **Servidor:** `drakkan/sftpgo:latest` (imatge oficial de SFTPGo)
- **Client:** `lscr.io/linuxserver/filezilla:latest` (imatge oficial de LinuxServer)
- **Router:** `frrouting/frr:latest`
- **DNS:** `coredns/coredns:latest`

```bash
# Construir la imatge del switch (unica imatge custom)
./lab.sh build
```

> **Nota:** Alternativament, pots construir-la directament amb:
> ```bash
> docker build -t sftpgo-lab/switch:latest docker/switch/
> ```

---

## Pas 2: Desplegar el laboratori

```bash
./lab.sh deploy 1
```

> **Nota:** Aquesta comanda requereix `sudo` (containerlab necessita privilegis
> per crear les interficies de xarxa).

Comprova que els contenidors estan actius:

```bash
./lab.sh status
```

Hauries de veure 5 nodes: `switch-lan`, `router-frr`, `server`, `client`, `coredns`.

---

## Pas 3: Accedir al client FileZilla via WebRTC

Obre el navegador al host i navega a:

```
https://localhost:3001
```

- **Contrasenya:** `labvnc`
- El navegador mostrar un avís de certificat autosignat. Accepta'l per continuar.
- S'obrira la interficie de FileZilla dins del navegador (via Selkies/WebRTC).

> **Alternativa (CLI):** Pots entrar al contenidor directament:
> ```bash
> ./lab.sh shell client
> ```

---

## Pas 4: Verificar l'usuari FTP a SFTPGo

L'usuari `ftpuser` es crea **automaticament** durant el desplegament del laboratori
(l'script `server-init.sh` el crea via l'API REST de SFTPGo). No cal crear-lo manualment.

### 4.1 Accedir al panell d'administracio

Obre al navegador del host:

```
http://localhost:8081/web/admin
```

**Credencials:**
- Usuari: `admin`
- Contrasenya: `admin`

### 4.2 Verificar que l'usuari existeix

1. Navega a **Users** al menu lateral
2. Hauries de veure l'usuari `ftpuser` ja creat amb:
   - **Username:** `ftpuser`
   - **Password:** `ftppassword`
   - **Home directory:** `/srv/sftpgo/data/ftpuser`
   - **Permissions:** `*` (totes les operacions)

### 4.3 Verificar que el servei FTP escolta al port 21

Des del servidor:

```bash
./lab.sh shell server
ss -tlnp | grep :21
```

Hauries de veure:

```
LISTEN   0   4096   *:21   *:*   users:(("sftpgo",pid=...,fd=...))
```

---

## Pas 5: Connectar amb FileZilla al servidor FTP

### 5.1 Des de la interficie grafica (WebRTC)

1. A la finestra de FileZilla al navegador, obre el **Gestor de llocs** (Site Manager: `Ctrl+S`)
2. Crea un nou lloc:
   - **Protocol:** FTP - Transferencia de fitxers
   - **Host:** `demoftp.test`
   - **Port:** `21`
   - **Mode de xifratge:** Usa FTP en text clar (No TLS)
   - **Tipus d'inici de sessio:** Normal
   - **Usuari:** `ftpuser`
   - **Contrasenya:** `ftppassword`
3. Fes clic a **Connecta**

### 5.2 Verificacio de la connexio

Hauries de veure al panell dret els fitxers del directori `/srv/sftpgo/data/ftpuser`.

---

## Pas 6: Capturar el trafic amb tcpdump

Aquest pas es fonamental per entendre per **que FTP es insegur**.

### 6.1 Des del contenidor client (o servidor)

```bash
./lab.sh shell client

# Capturar tot el trafic FTP a la interficie LAN
tcpdump -i eth1 -w /tmp/captura-ftp.pcap port 21 or portrange 50000-50100
```

Mentres captures, fes una transferencia des de FileZilla.

### 6.2 Llegir la captura

```bash
# Veure el contingut en text pla (veuràs usuari i contrasenya!)
tcpdump -r /tmp/captura-ftp.pcap -A | grep -E "USER|PASS|^220|^230"
```

**Resultat esperat:**
```
... USER ftpuser
... PASS ftppassword    <-- LA CONTRASENYA ES VEU EN CLAR!
```

> **Reflexio:** Quines dades d'un usuari queden exposades en una captura FTP?

---

## Pas 7: Transferir fitxers i verificar

### 7.1 Crear un fitxer de prova al client

```bash
./lab.sh shell client
echo "Hola des del laboratori FTP!" > /tmp/prova.txt
```

### 7.2 Pujar el fitxer via FileZilla

Des de la GUI de FileZilla:
1. Navega a `/tmp/` al panell **Local**
2. Arrossega `prova.txt` al panell **Remot**

### 7.3 Verificar al servidor

```bash
./lab.sh shell server
cat /srv/sftpgo/data/ftpuser/prova.txt
```

---

## Pas 8: Provar FTP des de la linia de comandes (curl)

Pots verificar el funcionament del servidor FTP des del contenidor client amb `curl`:

```bash
./lab.sh shell client

# Llistar fitxers del directori remot
curl -v ftp://ftpuser:ftppassword@demoftp.test/

# Pujar un fitxer
curl -s ftp://ftpuser:ftppassword@demoftp.test/ -T /etc/hostname

# Descarregar un fitxer
curl -o /tmp/descarregat.txt ftp://ftpuser:ftppassword@demoftp.test/prova.txt
```

---

## Pas 9: Verificar la resolucio de noms DNS

```bash
./lab.sh shell client

# Resolucio directa
dig demoftp.test @10.50.0.53
nslookup demoftp.test

# Resolucio inversa
dig -x 10.50.0.20 @10.50.0.53

# Ping per nom
ping -c 3 demoftp.test
```

---

## Pas 10: Consultar els logs del servidor

Pots veure els logs de SFTPGo en temps real:

```bash
./lab.sh logs server
```

---

## Pas 11: Aturar el laboratori

```bash
./lab.sh destroy
```

---

## Resum de l'Etapa 1

| Aspecte | Valor |
|---------|-------|
| Protocol | FTP (port 21) |
| Xifrat | Cap (text pla) |
| Autenticacio | Usuari/Contrasenya en clar |
| Emmagatzematge | Local (`/srv/sftpgo/data`) |
| DNS | CoreDNS --> `demoftp.test` |
| Client GUI | FileZilla via Selkies/WebRTC (port 3001, HTTPS) |
| Admin web | `http://localhost:8081/web/admin` |
| Topologia | `topologies/etapa1.yml` |
| Usuari FTP | `ftpuser` / `ftppassword` (creat automaticament) |

---

## Observacions importants

- El protocol FTP **transmet usuari i contrasenya en text pla**
- Les dades transferides **no estan xifrades**
- Qualsevol node a la xarxa pot fer un atac **man-in-the-middle**
- La **Etapa 2** resoldrà aquests problemes amb FTPS/FTPES i mkcert

---

## Preguntes de reflexio — Etapa 1

1. Quin port utilitza el mode FTP actiu vs. passiu per a la transferencia de dades? Quines implicacions te per al firewall?
2. Quan heu capturat el trafic amb tcpdump, quina informacio sensible heu pogut veure? Quins riscos de seguretat representa?
3. Per quins motius FTP segueix sent ampliament usat en entorns interns malgrat els seus riscos de seguretat?
4. Quina diferencia hi ha entre el mode actiu i el mode passiu en FTP? Quin s'utilitza per defecte a FileZilla?
5. Qui controla la politica de ports passius? Quins avantatges te definir un rang de ports reduit (`50000-50100`)?
6. Quin es el codi de resposta FTP que indica que l'inici de sessio ha estat correcte? I el que indica que el directori ha canviat?
7. Compara el rendiment de transferencia entre FTP i SFTP. Quin factores influencien la diferencia?
8. Com afecta la presencia d'un NAT entre el client i el servidor al mode actiu de FTP? Com es resol?
9. Per quina rao SFTPGo no es un servidor FTP tradicional? Quin es el seu avantatge des del punt de vista operatiu?
10. Explica el paper que juga el bridge Linux al contenidor `switch-lan`. Per quin motiu es millor aquesta aproximacio que usar un switch de Linux real en un lab containerlab?
