# Laboratori FTP amb SFTPGo — Etapa 6: Proxy invers i hosting web des del FTP

## Objectiu

Desplegar un **proxy invers nginx** que serveixi tres llocs web (`web01`, `web02`, `web03.demoftp.test`) on el contingut de cadascun prové d'un **directori diferent del servidor FTP** (SFTPGo). Els servidors web interiors (`web01`, `web02`) usaran **nginx**, i `web03` usarà **Angie** (fork modern de nginx). Aprendrem virtual hosting per nom, proxy invers, i la relació entre FTP i hosting web estàtic.

---

## Arquitectura de la xarxa

```
Host Linux (tu)
  │
  ├─ http://localhost:8091  → Proxy invers (web01/web02/web03 per Host header)
  ├─ https://localhost:8081 → SFTPGo Web Admin

  Xarxa LAN: 10.50.0.0/24
  ┌─────────────────────────────────────────────────────────────────────────┐
  │  [client]    10.50.0.10   FileZilla + WebRTC / Selkies (GUI FTP)           │
  │  [server]    10.50.0.20   SFTPGo — contingut FTP (web01/ web02/ web03/)│
  │  [proxy]     10.50.0.60   nginx proxy invers          ← NOU            │
  │  [web01]     10.50.0.61   nginx → /var/www/web01      ← NOU            │
  │  [web02]     10.50.0.62   nginx → /var/www/web02      ← NOU            │
  │  [web03]     10.50.0.63   Angie → /var/www/web03      ← NOU            │
  │  [coredns]   10.50.0.53   DNS                                          │
  │  [router]    10.50.0.1    FRR (gateway LAN)                            │
  └─────────────────────────────────────────────────────────────────────────┘

  Flux de peticions web:
    Navegador → proxy (10.50.0.60) → web01/web02/web03 (per Host header)
               └─ web01.demoftp.test → 10.50.0.61 (nginx)
               └─ web02.demoftp.test → 10.50.0.62 (nginx)
               └─ web03.demoftp.test → 10.50.0.63 (Angie)

  Flux del contingut (FTP → Web):
    Usuari FTP puja fitxers a /web01/, /web02/, /web03/ via SFTPGo
    Els nodes web sincronitzen el contingut via lftp mirror
```

**Dominis nous:** `web01.demoftp.test` → 10.50.0.61, `web02.demoftp.test` → 10.50.0.62, `web03.demoftp.test` → 10.50.0.63

---

## Prerequisits

- Etapes 1 i 2 completades (SFTPGo funcional + certificats mkcert)
- Imatges Docker construïdes: `sftpgo-lab/proxy`, `sftpgo-lab/web-nginx`, `sftpgo-lab/web-angie`
- Nodes inclosos a `topologies/etapa6.yml`

---

## Pas 1: Activar els nodes a la topologia

La topologia `topologies/etapa6.yml` ja inclou els nodes `proxy`, `web01`, `web02` i `web03` amb tota la configuració necessària (IPs, ports, links, binds i scripts d'inicialització). No cal editar ni descomentar res manualment.

Els registres DNS corresponents també ja estan configurats a les zones de CoreDNS.

Per desplegar el laboratori d'aquesta etapa:

```bash
./lab.sh deploy 6
```

---

## Pas 2: Construir les imatges i redesplegar

```bash
# Construir totes les imatges (inclou les noves)
./lab.sh build

# Destruir i redesplegar
./lab.sh destroy
./lab.sh deploy 6
```

---

## Pas 3: Executar el script de configuració

```bash
./lab.sh setup6
```

El script `setup-etapa6.sh`:
1. Crea el contingut HTML de prova per a web01, web02 i web03 al servidor FTP
2. Configura nginx a `web01` i `web02` per servir des de `/var/www/web01` i `/var/www/web02`
3. Configura Angie a `web03` per servir des de `/var/www/web03`
4. Configura nginx al node `proxy` com a proxy invers per als tres vhosts
5. Sincronitza el contingut des del servidor FTP als nodes web via `lftp mirror`

---

## Pas 4: Comprendre la configuració del proxy invers

El proxy invers té tres server blocks — un per cada vhost:

```nginx
# /etc/nginx/sites-available/proxy-lab

server {
    listen 80;
    server_name web01.demoftp.test;

    location / {
        proxy_pass         http://10.50.0.61:80;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
    add_header X-Proxy "nginx-proxy" always;
}

server {
    listen 80;
    server_name web02.demoftp.test;
    location / {
        proxy_pass http://10.50.0.62:80;
        # ...mateixos proxy_set_header...
    }
}

server {
    listen 80;
    server_name web03.demoftp.test;
    location / {
        proxy_pass http://10.50.0.63:80;
        # ...mateixos proxy_set_header...
    }
}
```

El proxy decideix cap a on enviar cada petició basant-se en la **capçalera `Host`** HTTP que envia el navegador.

---

## Pas 5: Comprendre Angie (web03)

**Angie** és un fork modern de nginx creat per una empresa russa (Wgnet). És 100% compatible amb la configuració de nginx però afegeix funcionalitats addicionals:

```nginx
# /etc/angie/http.d/web03.conf — Configuració Angie

server {
    listen 80;
    server_name web03.demoftp.test;

    root /var/www/web03;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    add_header X-Served-By "angie-web03" always;
    add_header X-Powered-By "Angie" always;
}
```

Diferències visibles respecte a nginx:
- Configuració a `/etc/angie/` (no `/etc/nginx/`)
- Comandes `angie` en lloc de `nginx`
- Capçalera `X-Powered-By: Angie` a les respostes
- Millor rendiment en connexions keepalive

---

## Pas 6: Verificació des del node proxy

```bash
# Entrar al node proxy
./lab.sh shell proxy

# Verificar que nginx escolta al port 80
ss -tlnp | grep :80

# Testejar cada vhost amb curl (des del proxy)
curl -H "Host: web01.demoftp.test" http://127.0.0.1/
curl -H "Host: web02.demoftp.test" http://127.0.0.1/
curl -H "Host: web03.demoftp.test" http://127.0.0.1/

# Verificar capçaleres de resposta
curl -I -H "Host: web01.demoftp.test" http://127.0.0.1/
curl -I -H "Host: web03.demoftp.test" http://127.0.0.1/
# Ha de mostrar: X-Served-By: angie-web03
```

---

## Pas 7: Verificació des del host

```bash
# Des del host (port 8091 mapat al proxy)
curl -H "Host: web01.demoftp.test" http://localhost:8091/
curl -H "Host: web02.demoftp.test" http://localhost:8091/
curl -H "Host: web03.demoftp.test" http://localhost:8091/

# Afegir al /etc/hosts del host per navegació directa amb el navegador:
echo "127.0.0.1  web01.demoftp.test web02.demoftp.test web03.demoftp.test" \
    | sudo tee -a /etc/hosts

# Ara pots obrir al navegador:
# http://web01.demoftp.test:8091
# http://web02.demoftp.test:8091
# http://web03.demoftp.test:8091
```

---

## Pas 8: Actualitzar contingut web via FTP

La gràcia del sistema és que el contingut web prové del servidor FTP. Per actualitzar-lo:

```bash
# 1. Pujar nou contingut via FileZilla (GUI, la interfície web) o lftp:
docker exec clab-sftpgo-lab-client lftp -u ftpuser,ftppassword demoftp.test -e "
    put /tmp/nou-index.html -o /web01/index.html
    bye
"

# 2. Sincronitzar el contingut FTP → servidor web:
docker exec clab-sftpgo-lab-web01 lftp -u ftpuser,ftppassword demoftp.test -e "
    set ftp:passive-mode yes
    set ftp:ssl-allow no
    mirror /web01/ /var/www/web01/
    bye
"

# 3. Verificar el resultat:
curl -H "Host: web01.demoftp.test" http://localhost:8091/
```

---

## Pas 9: Comparativa nginx vs Angie

| Característica | nginx | Angie |
|----------------|-------|-------|
| Origen | Igor Sysoev (Nginx, Inc.) | Wgnet (fork nginx, 2022) |
| Llicència | BSD 2-Clause | BSD 2-Clause |
| Compatibilitat config | — | 100% compatible amb nginx |
| Ubicació config | `/etc/nginx/` | `/etc/angie/` |
| Rendiment keepalive | Base | Millores addicionals |
| Mòduls addicionals | Via compilació | Alguns integrats |
| Versió Ubuntu 24.04 | Repositori oficial | Repositori propi Angie |
| Ús típic | Molt estès | Alternativa a nginx |

---

## Pas 10: Diagnosi i logs

```bash
# Logs del proxy invers
docker exec clab-sftpgo-lab-proxy tail -f /var/log/nginx/access.log
docker exec clab-sftpgo-lab-proxy tail -f /var/log/nginx/error.log

# Logs de web01/web02 (nginx)
docker exec clab-sftpgo-lab-web01 tail -f /var/log/nginx/access.log

# Logs de web03 (Angie)
docker exec clab-sftpgo-lab-web03 tail -f /var/log/angie/access.log

# Verificar configuració nginx del proxy
docker exec clab-sftpgo-lab-proxy nginx -t

# Verificar configuració Angie de web03
docker exec clab-sftpgo-lab-web03 angie -t

# Tcpdump per veure el tràfic HTTP al proxy
docker exec clab-sftpgo-lab-proxy tcpdump -i eth1 -n port 80
```

---

## Taula resum de l'Etapa 6

| Node | IP | Servei | Rol | Contingut |
|------|----|--------|-----|-----------|
| server | 10.50.0.20 | SFTPGo | Font de contingut FTP | `/web01/`, `/web02/`, `/web03/` |
| proxy | 10.50.0.60 | nginx | Proxy invers (vhost per nom) | Enruta per `Host:` header |
| web01 | 10.50.0.61 | nginx | Servidor web intern | Sincronitzat des de FTP `/web01/` |
| web02 | 10.50.0.62 | nginx | Servidor web intern | Sincronitzat des de FTP `/web02/` |
| web03 | 10.50.0.63 | Angie | Servidor web intern | Sincronitzat des de FTP `/web03/` |

---

## Preguntes de reflexió

1. **Quin és el rol exacte del proxy invers en aquesta arquitectura?** Per qué no servim el contingut web directament des de cada servidor web (sense proxy)?

2. **Explica el mecanisme de `virtual hosting per nom de host`.** Quin camp de la petició HTTP permet al proxy diferenciar entre `web01`, `web02` i `web03`?

3. **Quina capçalera HTTP envia el proxy als servidors interns per preservar la IP original del client?** Per qué és important per als logs?

4. **Descriu el flux complet des que un usuari puja un fitxer via FileZilla fins que apareix al web.** Quants passos manuals cal fer? Com es podria automatitzar?

5. **Angie és compatible amb la configuració de nginx però usa `/etc/angie/` en lloc de `/etc/nginx/`.** Quin avantatge i quin inconvenient té mantenir fitxers de configuració en rutes diferents per a dos serveis similars?

6. **En producció, el proxy invers normalment termina TLS (HTTPS).** Descriu com caldria modificar la configuració del node `proxy` per afegir HTTPS als tres vhosts usant els certificats mkcert del lab.

7. **El contingut web es sincronitza manualment via `lftp mirror`.** Quins mecanismes existeixen per automatitzar aquesta sincronització (cron, inotify, webhooks SFTPGo, etc.)?

8. **Compara les capçaleres `X-Served-By` i `X-Proxy` que afegim.** En quin node s'afegeix cadascuna? Quin valor tenen per al diagnosi de problemes?

9. **Quina diferència hi ha entre `proxy_pass http://10.50.0.61:80` i `proxy_pass http://web01.demoftp.test:80` a la configuració del proxy?** Quin depèn del DNS i quins problemes pot causar?

10. **En una arquitectura de producció real, s'usaria un proxy invers com a punt únic d'entrada per múltiples webs?** Descriu una arquitectura amb nginx + Let's Encrypt + múltiples servidors web interns i explica quines parts coincideixen amb el que hem fet al lab.
