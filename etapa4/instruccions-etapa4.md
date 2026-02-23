# Laboratori FTP amb SFTPGo — Etapa 4: Autenticació federada amb Keycloak (OIDC)

## Objectiu

Integrar **Keycloak** com a proveïdor d'identitat (IdP) OpenID Connect i configurar SFTPGo per autenticar els usuaris FTP contra Keycloak en lloc d'una base de dades local. Això representa un patró d'autenticació federada real on una única font de veritat (Keycloak) gestiona els usuaris de múltiples serveis.

---

## Arquitectura de la xarxa

```
Host Linux (tu)
  │
  ├─ https://localhost:3001  → WebRTC / Selkies (FileZilla GUI)
  ├─ https://localhost:8081 → SFTPGo Web Admin (HTTPS)
  ├─ http://localhost:9001  → RustFS / MinIO Console
  └─ http://localhost:8180  → Keycloak Admin Console

  Xarxa LAN: 10.50.0.0/24
  ┌───────────────────────────────────────────────────────────────┐
  │  [client]    10.50.0.10  FileZilla + WebRTC (Selkies)          │
  │  [server]    10.50.0.20  SFTPGo (auth → Keycloak OIDC)        │
  │  [coredns]   10.50.0.53  DNS                                  │
  │  [router]    10.50.0.1   FRR (gateway LAN)                    │
  │  [switch]                Linux bridge                         │
  │  [rustfs]    10.50.0.30  RustFS / MinIO (S3)                  │
  │  [keycloak]  10.50.0.40  Keycloak IdP (OIDC)             ←NOU │
  └───────────────────────────────────────────────────────────────┘

  Flux d'autenticació:
    Client FTP → SFTPGo → hook OIDC → Keycloak → token JWT → OK/KO
```

**Dominis nous:** `keycloak.test` → 10.50.0.40

---

## Prerequisits

- Etapes 1, 2 i 3 completades
- Imatge Keycloak disponible: `docker pull quay.io/keycloak/keycloak:latest`
- Familiaritat bàsica amb OAuth2/OIDC (conceptes: realm, client, token JWT)

---

## Pas 1: Activar el node Keycloak a la topologia

La topologia `topologies/etapa4.yml` ja inclou el node Keycloak amb tota la configuració necessària (IP, ports, links). No cal editar ni descomentar res manualment.

Per desplegar el laboratori d'aquesta etapa:

```bash
./lab.sh deploy 4
```

---

## Pas 2: Actualitzar la zona DNS

Edita `configs/coredns/zones/db.test`:

```
keycloak IN  A   10.50.0.40
```

I `configs/coredns/zones/db.50.10.in-addr.arpa`:

```
40  IN  PTR keycloak.test.
```

Recorda incrementar el serial SOA.

---

## Pas 3: Desplegar el laboratori ampliat

```bash
./lab.sh destroy
./lab.sh deploy 4
```

Verifica els 7 nodes actius:

```bash
./lab.sh status
```

---

## Pas 4: Configurar la xarxa del node Keycloak

```bash
docker exec clab-sftpgo-lab-keycloak bash -c "
    ip addr add 10.50.0.40/24 dev eth1
    ip link set eth1 up
    ip route add default via 10.50.0.1 dev eth1
"
```

---

## Pas 5: Arrancar Keycloak

Keycloak arrenca en mode *development* (HTTP, sense TLS) per simplicitat del laboratori:

```bash
docker exec -d clab-sftpgo-lab-keycloak \
    /opt/keycloak/bin/kc.sh start-dev \
    --http-port=8080 \
    --hostname=keycloak.test \
    --hostname-strict=false
```

Espera uns 30-60 segons i verifica que respon:

```bash
curl -s http://localhost:8180/realms/master | python3 -m json.tool | head -5
```

---

## Pas 6: Crear el realm "lab" i el client "sftpgo"

### 6.1 Accedir a la consola d'administració

```
http://localhost:8180/admin
```

- **Usuari:** `admin`
- **Contrasenya:** `admin`

### 6.2 Crear el realm "lab"

1. A la barra lateral, fes clic al desplegable del realm actual (`master`)
2. Selecciona **Create realm**
3. **Realm name:** `lab`
4. **Enabled:** On
5. Fes clic a **Create**

### 6.3 Crear el client "sftpgo"

Dins del realm `lab`:

1. Navega a **Clients → Create client**
2. **Client ID:** `sftpgo`
3. **Client type:** OpenID Connect
4. Fes clic a **Next**
5. Habilita:
   - **Client authentication:** On (confidential client)
   - **Standard flow:** On
   - **Direct access grants:** On (necessari per a autenticació FTP)
6. **Valid redirect URIs:** `http://demoftp.test:8080/*`
7. Fes clic a **Save**

### 6.4 Obtenir el Client Secret

1. Navega a **Clients → sftpgo → Credentials**
2. Copia el valor de **Client secret** (el farem servir al pas 8)

---

## Pas 7: Crear usuaris al realm "lab"

### 7.1 Crear l'usuari ftpuser

1. Navega a **Users → Add user**
2. **Username:** `ftpuser`
3. **Email verified:** On
4. Fes clic a **Create**
5. Ves a la pestanya **Credentials**:
   - **Password:** `ftppassword`
   - **Temporary:** Off
   - Fes clic a **Set password**

### 7.2 (Opcional) Crear un segon usuari per provar el control d'accés

Repeteix el pas anterior amb `ftpuser2` / `ftppassword2`.

---

## Pas 8: Configurar SFTPGo per usar Keycloak

SFTPGo suporta autenticació externa via un *hook* (script extern). El hook fa una petició OIDC/OAuth2 al token endpoint de Keycloak per verificar les credencials.

### 8.1 Crear el hook d'autenticació

Dins del contenidor `server`, crea l'script `/usr/local/bin/auth-keycloak.sh`:

```bash
docker exec clab-sftpgo-lab-server bash -c "cat > /usr/local/bin/auth-keycloak.sh << 'HOOK'
#!/bin/bash
# Hook d'autenticació externa per a SFTPGo → Keycloak

# SFTPGo passa les credencials via stdin en format JSON
read -r INPUT
USERNAME=\$(echo \"\$INPUT\" | python3 -c \"import sys,json; d=json.load(sys.stdin); print(d.get('username',''))\" 2>/dev/null)
PASSWORD=\$(echo \"\$INPUT\" | python3 -c \"import sys,json; d=json.load(sys.stdin); print(d.get('password',''))\" 2>/dev/null)

KEYCLOAK_URL='http://keycloak.test:8080'
REALM='lab'
CLIENT_ID='sftpgo'
CLIENT_SECRET='SUBSTITUEIX_AMB_EL_CLIENT_SECRET'

RESPONSE=\$(curl -s -X POST \
  \"\${KEYCLOAK_URL}/realms/\${REALM}/protocol/openid-connect/token\" \
  -d \"client_id=\${CLIENT_ID}\" \
  -d \"client_secret=\${CLIENT_SECRET}\" \
  -d \"grant_type=password\" \
  -d \"username=\${USERNAME}\" \
  -d \"password=\${PASSWORD}\")

ACCESS_TOKEN=\$(echo \"\$RESPONSE\" | python3 -c \"import sys,json; print(json.load(sys.stdin).get('access_token',''))\" 2>/dev/null)

if [ -n \"\$ACCESS_TOKEN\" ] && [ \"\$ACCESS_TOKEN\" != 'null' ]; then
  # Autenticació correcta: retornar usuari vàlid per a SFTPGo
  echo '{\"username\":\"\$USERNAME\",\"home_dir\":\"/srv/sftpgo/data/\$USERNAME\",\"permissions\":{\"/\":[\"*\"]},\"status\":1}'
else
  # Autenticació incorrecta
  echo '{\"username\":\"\"}'
fi
HOOK"

docker exec clab-sftpgo-lab-server chmod +x /usr/local/bin/auth-keycloak.sh
"
```

**Important:** Substitueix `SUBSTITUEIX_AMB_EL_CLIENT_SECRET` pel secret obtingut al pas 6.4.

### 8.2 Reconfigurar SFTPGo

Atura SFTPGo i arrenca'l amb la configuració de l'etapa 4:

```bash
docker exec clab-sftpgo-lab-server pkill sftpgo || true
sleep 2

docker exec -d clab-sftpgo-lab-server \
    sftpgo serve --config-file /etc/sftpgo/etapa4/sftpgo.json
```

---

## Pas 9: Verificar l'autenticació via Keycloak

### 9.1 Obtenir un token JWT directament (prova de Keycloak)

```bash
# Des del contenidor client
docker exec clab-sftpgo-lab-client curl -s -X POST \
  "http://keycloak.test:8080/realms/lab/protocol/openid-connect/token" \
  -d "client_id=sftpgo" \
  -d "client_secret=SUBSTITUEIX_AMB_EL_CLIENT_SECRET" \
  -d "grant_type=password" \
  -d "username=ftpuser" \
  -d "password=ftppassword" | python3 -m json.tool | grep "access_token"
```

Si Keycloak funciona correctament, rebràs un `access_token` (JWT).

### 9.2 Connectar amb FileZilla via FTPES

Obre FileZilla a la interfície web (`https://localhost:3001`) i connecta a:

- **Host:** `demoftp.test` | **Port:** `21` | **Mode:** FTPES
- **Usuari:** `ftpuser` | **Contrasenya:** `ftppassword`

SFTPGo cridarà el hook, el hook autenticarà contra Keycloak, i la connexió s'establirà.

### 9.3 Provar credencials incorrectes

Intenta connectar amb una contrasenya incorrecta. Hauries de rebre un error d'autenticació.

---

## Pas 10: Inspeccionar el token JWT

Copia el `access_token` del pas 9.1 i decodifica'l:

```bash
docker exec clab-sftpgo-lab-client bash -c "
TOKEN='ENGANXA_EL_TOKEN_AQUÍ'
# Decodificar la part payload (base64 URL)
echo \$TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool
"
```

Observa els camps: `sub` (usuari), `iss` (issuer = Keycloak), `exp` (expiració), `preferred_username`.

---

## Resum de l'Etapa 4

| Aspecte | Etapa 3 | Etapa 4 |
|---------|---------|---------|
| Autenticació | Base de dades SFTPGo | Keycloak OIDC (extern) |
| Gestió d'usuaris | SFTPGo admin | Keycloak realm "lab" |
| Protocol auth | Usuari/password local | OAuth2 password grant |
| Escalabilitat | Un servidor SFTPGo | Múltiples serveis → un IdP |
| Token | No n'hi ha | JWT (accés + refresh) |
| Nodes actius | 6 | 7 (+ keycloak) |

---

## Preguntes de reflexió — Etapa 4

1. Quina diferència hi ha entre **OAuth2** i **OpenID Connect (OIDC)**? Quin afegeix OIDC per sobre d'OAuth2 que el fa adequat per a autenticació?
2. En aquest laboratori s'usa el flux **Resource Owner Password Credentials (ROPC)**. Per quina raó aquest flux no és recomanable en producció? Quins fluxos alternatius hi ha per a aplicacions de servidor?
3. Un token JWT té tres parts: capçalera, payload i signatura. Quines dades del payload (`claims`) té rellevància per a l'autorització a SFTPGo?
4. Si el servidor Keycloak és temporalment inaccesible, els usuaris FTP podran autenticar-se? Com dissenyaries un sistema de fallback o caché de credencials?
5. Quina diferència hi ha entre un **realm** i un **client** a Keycloak? Per quina raó s'ha creat un realm `lab` separat del realm `master`?
6. El hook d'autenticació és un script Bash que fa una petició HTTP. Quins problemes de seguretat pot tenir aquest enfocament? (Pensa en secrets en text pla, condicions de carrera, injecció de comandes.)
7. Compara la gestió d'usuaris centralitzada (Keycloak) amb la distribuïda (base de dades local de SFTPGo). Quins avantatges té cadascuna en termes de seguretat, auditoria i manteniment?
8. Keycloak pot expirar els tokens (camp `exp`). Com afecta l'expiració del token a una sessió FTP ja establerta i activa?
9. Si afegissis un segon servidor SFTPGo (per alta disponibilitat), com gestionaria Keycloak les sessions i els tokens entre les dues instàncies?
10. OAuth2/OIDC s'usa habitualment per a aplicacions web. Per quina raó el seu ús per a autenticació FTP és poc comú en producció? Quines alternatives estandarditzades (LDAP, RADIUS, PAM) s'usen normalment per a servidors FTP?
