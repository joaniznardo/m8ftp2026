# Laboratori FTP amb SFTPGo — Etapa 3: Emmagatzematge extern amb RustFS (S3)

## Objectiu

Afegir un node **RustFS** com a backend d'emmagatzematge compatible S3 i configurar SFTPGo perquè tots els fitxers dels usuaris FTP es guarden directament en un bucket S3, en lloc del sistema de fitxers local. Això representa un patró real de producció on el servidor FTP és sense estat (*stateless*) i l'emmagatzematge és escalable i independent.

> **Nota:** Aquesta etapa és un stub formatiu. RustFS no és un projecte publicat
> amb una imatge Docker estable. En funció de la disponibilitat de la imatge
> oficial, podeu substituir RustFS per **MinIO** (`minio/minio:latest`), que
> és 100% compatible amb l'API S3 i té el mateix comportament als passos
> d'aquest laboratori.

---

## Arquitectura de la xarxa

```
Host Linux (tu)
  │
  ├─ https://localhost:3001  → WebRTC / Selkies (FileZilla GUI)
  ├─ http://localhost:8081  → SFTPGo Web Admin
  └─ http://localhost:9001  → RustFS / MinIO Console

  Xarxa LAN: 10.50.0.0/24
  ┌──────────────────────────────────────────────────────┐
  │  [client]   10.50.0.10  FileZilla + WebRTC (Selkies)   │
  │  [server]   10.50.0.20  SFTPGo (backend → S3)        │
  │  [coredns]  10.50.0.53  DNS (demoftp.test)           │
  │  [router]   10.50.0.1   FRR (gateway LAN)            │
  │  [switch]               Linux bridge                 │
  │  [rustfs]   10.50.0.30  RustFS / MinIO (S3 API)  ←NOU│
  └──────────────────────────────────────────────────────┘
```

**Domini:** `demoftp.test` → 10.50.0.20 | `rustfs.test` → 10.50.0.30

---

## Prerequisits

- Etapes 1 i 2 completades (contenidors construïts, certificats mkcert disponibles)
- Imatge RustFS o MinIO disponible localment (`docker pull minio/minio:latest`)

---

## Pas 1: Activar el node RustFS a la topologia

La topologia `topologies/etapa3.yml` ja inclou el node RustFS amb tota la configuració necessària (IP, ports, links). No cal editar ni descomentar res manualment.

Per desplegar el laboratori d'aquesta etapa:

```bash
./lab.sh deploy 3
```

---

## Pas 2: Actualitzar la zona DNS

Edita `configs/coredns/zones/db.test` i afegeix:

```
rustfs   IN  A   10.50.0.30
```

I `configs/coredns/zones/db.50.10.in-addr.arpa`:

```
30  IN  PTR rustfs.test.
```

Recorda incrementar el serial SOA (`YYYYMMDDNN`).

---

## Pas 3: Desplegar el laboratori ampliat

```bash
# Destruir el lab anterior (si estava en marxa)
./lab.sh destroy

# Desplegar amb el nou node
./lab.sh deploy 3
```

Verifica que el nou node apareix:

```bash
./lab.sh status
```

---

## Pas 4: Configurar la xarxa del node RustFS

El node RustFS necessita la seva IP a eth1. Executa des del host:

```bash
docker exec clab-sftpgo-lab-rustfs bash -c "
    ip addr add 10.50.0.30/24 dev eth1
    ip link set eth1 up
    ip route add default via 10.50.0.1 dev eth1
"
```

Verifica la connectivitat:

```bash
docker exec clab-sftpgo-lab-rustfs ping -c 3 10.50.0.20
```

---

## Pas 5: Crear el bucket S3 a RustFS/MinIO

### 5.1 Via la consola web

Obre al navegador del host:

```
http://localhost:9001
```

- **Usuari:** `rustfs-access-key`
- **Contrasenya:** `rustfs-secret-key`

Crea un bucket anomenat `sftpgo-data` amb accés privat.

### 5.2 Via línia de comandes (mc — MinIO Client)

```bash
# Instal·lar mc al client (si cal)
docker exec clab-sftpgo-lab-client bash -c "
    curl -Lo /usr/local/bin/mc \
      https://dl.min.io/client/mc/release/linux-amd64/mc
    chmod +x /usr/local/bin/mc
"

# Configurar l'alias
docker exec clab-sftpgo-lab-client mc alias set rustfs \
    http://rustfs.test:9000 \
    rustfs-access-key \
    rustfs-secret-key

# Crear el bucket
docker exec clab-sftpgo-lab-client mc mb rustfs/sftpgo-data

# Verificar
docker exec clab-sftpgo-lab-client mc ls rustfs/
```

---

## Pas 6: Reconfigurar SFTPGo per usar el backend S3

### 6.1 Aturar SFTPGo al servidor

```bash
docker exec clab-sftpgo-lab-server pkill sftpgo || true
```

### 6.2 Arrancar amb la configuració de l'etapa 3

```bash
docker exec clab-sftpgo-lab-server \
    sftpgo serve --config-file /etc/sftpgo/etapa3/sftpgo.json &
```

### 6.3 Verificar la connexió S3

SFTPGo registrarà la connexió S3 als logs:

```bash
docker logs clab-sftpgo-lab-server | grep -i "s3\|bucket\|rustfs"
```

---

## Pas 7: Crear un usuari FTP amb virtual filesystem S3

Al panell d'administració de SFTPGo (`https://localhost:8081/web/admin`):

1. Navega a **Users → Add User**
2. **Username:** `ftpuser`
3. A la secció **Filesystem**:
   - **Storage:** S3 Compatible
   - **Endpoint:** `http://rustfs.test:9000`
   - **Bucket:** `sftpgo-data`
   - **Region:** `us-east-1` (o buida)
   - **Access Key:** `rustfs-access-key`
   - **Access Secret:** `rustfs-secret-key`
   - **Key Prefix:** `ftpuser/` (separació per usuari dins del bucket)
4. Fes clic a **Save**

---

## Pas 8: Transferir fitxers i verificar al bucket

### 8.1 Pujar un fitxer des de FileZilla (la interfície web)

Connecta amb FileZilla a `demoftp.test:21` (FTPES) via la interfície web (`https://localhost:3001`) i puja un fitxer de prova.

### 8.2 Verificar que el fitxer és al bucket S3

```bash
docker exec clab-sftpgo-lab-client mc ls rustfs/sftpgo-data/ftpuser/
```

Hauries de veure el fitxer que has pujat via FTP.

### 8.3 Descarregar el fitxer directament des del bucket

```bash
docker exec clab-sftpgo-lab-client \
    mc get rustfs/sftpgo-data/ftpuser/prova.txt /tmp/prova-s3.txt

docker exec clab-sftpgo-lab-client cat /tmp/prova-s3.txt
```

---

## Pas 9: Observar el tràfic S3 (HTTP)

Captura el tràfic entre SFTPGo i RustFS mentre fas una transferència FTP:

```bash
docker exec clab-sftpgo-lab-server \
    tcpdump -i eth1 -A port 9000 -w /tmp/captura-s3.pcap &

# Fes una transferència via FileZilla...

docker exec clab-sftpgo-lab-server pkill tcpdump || true
docker exec clab-sftpgo-lab-server \
    tcpdump -r /tmp/captura-s3.pcap -A | grep -E "PUT|GET|POST" | head -20
```

> **Reflexió:** El tràfic entre SFTPGo i el bucket S3 és HTTP (no xifrat en
> aquest laboratori). En producció, caldria habilitar TLS també a l'endpoint S3.

---

## Pas 10: Aturar el laboratori

```bash
./lab.sh destroy
```

---

## Resum de l'Etapa 3

| Aspecte | Etapa 2 | Etapa 3 |
|---------|---------|---------|
| Protocol FTP | FTPES (21) + FTPS (990) | FTPES (21) + FTPS (990) |
| Xifrat FTP | TLS 1.2+ | TLS 1.2+ |
| Emmagatzematge | Local (`/srv/sftpgo/data`) | S3 (RustFS/MinIO) |
| Backend | Filesystem | API S3 compatible |
| Escalabilitat | Limitada per disc | Alta (objectes S3) |
| Nodes actius | 5 | 6 (+ rustfs) |

---

## Preguntes de reflexió — Etapa 3

1. Quin avantatge operatiu té usar un backend S3 en lloc d'un filesystem local per al servidor FTP? Pensa en escalabilitat, alta disponibilitat i backup.
2. Quan SFTPGo usa el backend S3, el fitxer es guarda primer en memòria o es fa un *streaming* directe al bucket? Quines implicacions té per a fitxers grans?
3. El protocol S3 usa `PUT` per a pujades i `GET` per a descàrregues. Com es mapegen les comandes FTP (`STOR`, `RETR`) a operacions S3 dins de SFTPGo?
4. En aquest laboratori, el tràfic entre SFTPGo (server) i RustFS és HTTP sense xifrat. En quin escenari real aquest tràfic no xifrat seria acceptable? I en quin no ho seria?
5. Si el servidor RustFS és temporalment inaccesible, quin error rep l'usuari FTP? Com podries afegir resiliència al sistema?
6. El paràmetre `key_prefix` permet separar els fitxers de cada usuari dins del bucket. Quines alternatives de separació existeixen (bucket per usuari, IAM policies, etc.) i quins avantatges té cadascuna?
7. Quina diferència hi ha entre la consistència eventual de S3 i la consistència immediata d'un filesystem local? Afecta el comportament de FileZilla?
8. Si un usuari esborra un fitxer via FTP, el fitxer desapareix immediatament del bucket? Quin mecanisme podries activar a MinIO/RustFS per protegir-te d'esborrades accidentals?
9. En producció, les credencials S3 (`access key` / `secret key`) no haurien d'estar en clar al `sftpgo.json`. Quines alternatives hi ha per gestionar secrets de forma segura en un entorn contenidors?
10. Compara l'arquitectura d'aquesta etapa (SFTPGo + S3) amb la d'un servidor SFTP tradicional. Quines diferències hi ha en manteniment, rendiment i seguretat?
