#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# lab.sh — Script de gestió del laboratori FTP/FTPS amb SFTPGo + Containerlab
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_NAME="sftpgo-lab"
TOPO_DIR="$SCRIPT_DIR/topologies"
STATE_FILE="$SCRIPT_DIR/.lab-stage"

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

# ─── Funció: obtenir el fitxer de topologia per a una etapa ──────────────────
get_topo() {
    local stage="${1:-}"
    if [ -z "$stage" ]; then
        # Intentar llegir l'etapa desplegada
        if [ -f "$STATE_FILE" ]; then
            stage=$(cat "$STATE_FILE")
        else
            error "No s'ha especificat cap etapa i no hi ha cap lab desplegat.\n  Ús: $0 deploy <1|2|3|4|5|6>"
        fi
    fi

    local topo="$TOPO_DIR/etapa${stage}.yml"
    if [ ! -f "$topo" ]; then
        error "No existeix el fitxer de topologia: $topo\n  Etapes disponibles: 1, 2, 3, 4, 5, 6"
    fi
    echo "$topo"
}

# ─── Funció: comprovar prerequisits ──────────────────────────────────────────
check_deps() {
    header "Comprovant prerequisits"
    local all_ok=true

    command -v docker &>/dev/null \
        && ok "Docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'OK')" \
        || { warn "Docker no trobat"; all_ok=false; }
    command -v containerlab &>/dev/null \
        && ok "Containerlab: $(containerlab version 2>/dev/null | head -1 || echo 'OK')" \
        || { warn "Containerlab no trobat (sudo bash -c \"\$(curl -sL https://get.containerlab.dev)\")"; all_ok=false; }
    command -v mkcert &>/dev/null \
        && ok "mkcert: $(mkcert --version 2>/dev/null || echo 'OK')" \
        || warn "mkcert no trobat (necessari per a l'Etapa 2+)"

    [ "$all_ok" = "false" ] && error "Alguns prerequisits falten. Instal·la'ls i torna a executar."
    ok "Tots els prerequisits OK"
}

# ─── Funció: construir imatges Docker personalitzades ────────────────────────
# Només construeix les imatges que encara són custom (switch, clients, web, proxy).
# Server (drakkan/sftpgo) i client FileZilla (linuxserver/filezilla) són oficials.
build() {
    local target="${1:-all}"
    header "Construint imatges Docker"

    case "$target" in
        switch)
            _build_image "sftpgo-lab/switch" "$SCRIPT_DIR/docker/switch/" ;;
        client-lftp)
            _build_image "sftpgo-lab/client-lftp" "$SCRIPT_DIR/docker/client-lftp/" ;;
        client-rclone)
            _build_image "sftpgo-lab/client-rclone" "$SCRIPT_DIR/docker/client-rclone/" ;;
        web-nginx)
            _build_image "sftpgo-lab/web-nginx" "$SCRIPT_DIR/docker/web-nginx/" ;;
        web-angie)
            _build_image "sftpgo-lab/web-angie" "$SCRIPT_DIR/docker/web-angie/" ;;
        proxy)
            _build_image "sftpgo-lab/proxy" "$SCRIPT_DIR/docker/proxy/" ;;
        all)
            _build_image "sftpgo-lab/switch" "$SCRIPT_DIR/docker/switch/"
            _build_image "sftpgo-lab/client-lftp" "$SCRIPT_DIR/docker/client-lftp/"
            _build_image "sftpgo-lab/client-rclone" "$SCRIPT_DIR/docker/client-rclone/"
            _build_image "sftpgo-lab/web-nginx" "$SCRIPT_DIR/docker/web-nginx/"
            _build_image "sftpgo-lab/web-angie" "$SCRIPT_DIR/docker/web-angie/"
            _build_image "sftpgo-lab/proxy" "$SCRIPT_DIR/docker/proxy/"
            ;;
        *)
            error "Imatge desconeguda: $target\n  Opcions: switch, client-lftp, client-rclone, web-nginx, web-angie, proxy, all" ;;
    esac

    ok "Construcció completada"
}

# ─── Funció auxiliar: construir una imatge ────────────────────────────────────
_build_image() {
    local name="$1"
    local context="$2"
    info "Construint ${name}:latest ..."
    docker build -t "${name}:latest" "$context" || error "Fallada construint $name"
    ok "${name}:latest"
}

# ─── Funció: determinar quines imatges custom necessita una etapa ────────────
_required_images_for_stage() {
    local stage="$1"
    # El switch és necessari per a totes les etapes
    echo "sftpgo-lab/switch"

    case "$stage" in
        5)
            echo "sftpgo-lab/client-lftp"
            echo "sftpgo-lab/client-rclone"
            ;;
        6)
            echo "sftpgo-lab/proxy"
            echo "sftpgo-lab/web-nginx"
            echo "sftpgo-lab/web-angie"
            ;;
    esac
}

# ─── Funció: desplegar el lab ─────────────────────────────────────────────────

# ─── Funció: configurar xarxa de CoreDNS (imatge scratch, sense shell) ───────
# La imatge oficial coredns/coredns no té shell ni iproute2.
# Configurem la xarxa des del host usant nsenter al namespace de xarxa.
_configure_coredns() {
    local container="clab-${LAB_NAME}-coredns"
    local ip="10.50.0.53"
    local gw="10.50.0.1"
    local iface="eth1"

    info "Configurant xarxa de CoreDNS (via nsenter)..."

    local pid
    pid=$(docker inspect -f '{{.State.Pid}}' "$container" 2>/dev/null || echo "")
    if [ -z "$pid" ] || [ "$pid" = "0" ]; then
        warn "No s'ha pogut obtenir el PID de $container. CoreDNS potser no s'ha desplegat."
        return
    fi

    # Esperar que la interfície aparega
    local found=false
    for i in $(seq 1 30); do
        if sudo nsenter -t "$pid" -n ip link show "$iface" &>/dev/null; then
            found=true
            break
        fi
        sleep 1
    done

    if [ "$found" = "false" ]; then
        warn "La interfície $iface no ha aparegut a $container."
        return
    fi

    sudo nsenter -t "$pid" -n ip addr add "${ip}/24" dev "$iface" 2>/dev/null || true
    sudo nsenter -t "$pid" -n ip link set "$iface" up
    sudo nsenter -t "$pid" -n ip route add default via "$gw" dev "$iface" 2>/dev/null || true

    ok "CoreDNS xarxa configurada: $iface → $ip/24, GW: $gw"
}

deploy() {
    local stage="${1:-}"
    [ -z "$stage" ] && error "Cal especificar l'etapa.\n  Ús: $0 deploy <1|2|3|4|5|6>"

    local topo
    topo=$(get_topo "$stage")
    header "Desplegant el laboratori — Etapa $stage"

    # Verificar que les imatges custom necessàries existeixen
    local missing=false
    while IFS= read -r img; do
        if ! docker image inspect "${img}:latest" &>/dev/null; then
            warn "Imatge ${img}:latest no trobada. Construint..."
            local short_name="${img#sftpgo-lab/}"
            _build_image "$img" "$SCRIPT_DIR/docker/${short_name}/"
        fi
    done < <(_required_images_for_stage "$stage")

    # Desplegar
    sudo containerlab deploy --topo "$topo"

    # ─── Post-deploy: configurar xarxa de CoreDNS (imatge scratch, sense shell)
    _configure_coredns

    # Guardar l'etapa desplegada
    echo "$stage" > "$STATE_FILE"

    echo ""
    ok "Laboratori desplegat — Etapa $stage"
    echo ""
    echo -e "  ${BOLD}Accés al client FileZilla (web):${NC}"
    echo -e "  → ${CYAN}https://localhost:3001/${NC}  (contrasenya: labvnc)"
    echo ""
    echo -e "  ${BOLD}Panell d'admin SFTPGo:${NC}"
    echo -e "  → ${CYAN}http://localhost:8081/web/admin${NC}  (admin / admin)"
    echo ""

    # Ports addicionals per etapa
    case "$stage" in
        3)
            echo -e "  ${BOLD}MinIO Console:${NC}"
            echo -e "  → ${CYAN}http://localhost:9001${NC}  (rustfs-access-key / rustfs-secret-key)"
            echo "" ;;
        4)
            echo -e "  ${BOLD}Keycloak Admin:${NC}"
            echo -e "  → ${CYAN}http://localhost:8180${NC}  (admin / admin)"
            echo "" ;;
        6)
            echo -e "  ${BOLD}Proxy invers:${NC}"
            echo -e "  → ${CYAN}http://localhost:8091${NC}  (web01/web02/web03 via Host header)"
            echo "" ;;
    esac

    echo -e "  ${BOLD}Nodes actius:${NC}"
    sudo containerlab inspect --topo "$topo" 2>/dev/null || true
}

# ─── Funció: destruir el lab ──────────────────────────────────────────────────
destroy() {
    header "Destruint el laboratori"
    local topo

    if [ -f "$STATE_FILE" ]; then
        local stage
        stage=$(cat "$STATE_FILE")
        topo=$(get_topo "$stage")
        info "Destruint etapa $stage..."
    else
        # Intentar destruir qualsevol lab amb el nom sftpgo-lab
        warn "No es coneix l'etapa desplegada. Provant amb containerlab..."
        # Buscar qualsevol topologia que funcioni
        for f in "$TOPO_DIR"/etapa*.yml; do
            if [ -f "$f" ]; then
                topo="$f"
                break
            fi
        done
        [ -z "${topo:-}" ] && error "No s'ha trobat cap fitxer de topologia."
    fi

    sudo containerlab destroy --topo "$topo" --cleanup 2>/dev/null \
        || warn "El lab potser ja estava aturat."
    rm -f "$STATE_FILE"
    ok "Laboratori destruït."
}

# ─── Funció: estat del lab ────────────────────────────────────────────────────
status() {
    header "Estat del laboratori"

    if [ -f "$STATE_FILE" ]; then
        local stage
        stage=$(cat "$STATE_FILE")
        local topo
        topo=$(get_topo "$stage")
        info "Etapa desplegada: $stage"
        sudo containerlab inspect --topo "$topo" 2>/dev/null || warn "El lab no sembla estar desplegat."
    else
        warn "No es coneix l'etapa desplegada."
    fi

    echo ""
    info "Contenidors Docker actius:"
    docker ps --filter "label=containerlab=$LAB_NAME" \
              --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
}

# ─── Funció: generar certificats (Etapa 2+) ───────────────────────────────────
certs() {
    header "Generant certificats TLS (mkcert)"

    command -v mkcert &>/dev/null || error "mkcert no instal·lat. Instal·la'l primer:\n  sudo apt install mkcert  o  brew install mkcert"

    local cert_dir="$SCRIPT_DIR/certs"
    mkdir -p "$cert_dir"

    # Instal·lar CA local si no existeix
    mkcert -install 2>/dev/null || true

    # Generar certificats per a demoftp.test
    info "Generant certificats per a: demoftp.test, server.test, localhost"
    mkcert -cert-file "$cert_dir/demoftp.test.crt" \
           -key-file "$cert_dir/demoftp.test.key" \
           demoftp.test server.test localhost 127.0.0.1 10.50.0.20

    # Assegurar que la clau siga llegible per SFTPGo (UID 1000)
    # mkcert genera la clau amb permisos 0600 root:root, però el contenidor
    # de SFTPGo corre com a UID 1000 i necessita poder-la llegir.
    chmod 644 "$cert_dir/demoftp.test.key"

    # Copiar la CA root per al client
    local ca_root
    ca_root=$(mkcert -CAROOT)
    cp "$ca_root/rootCA.pem" "$cert_dir/rootCA.pem"

    ok "Certificats generats a $cert_dir/"
    echo -e "  ${CYAN}demoftp.test.crt${NC}  → Certificat del servidor"
    echo -e "  ${CYAN}demoftp.test.key${NC}  → Clau privada"
    echo -e "  ${CYAN}rootCA.pem${NC}        → CA root (per als clients)"
}

# ─── Funció: accedir a un node ────────────────────────────────────────────────
shell() {
    local node="${1:-client}"
    info "Connectant al node: $node"
    docker exec -it "clab-${LAB_NAME}-${node}" bash \
        || docker exec -it "clab-${LAB_NAME}-${node}" sh
}

# ─── Funció: mostrar logs d'un node ──────────────────────────────────────────
logs() {
    local node="${1:-server}"
    info "Logs del node: $node"
    docker logs -f "clab-${LAB_NAME}-${node}"
}

# ─── Funció: ajuda ────────────────────────────────────────────────────────────
usage() {
    echo ""
    echo -e "${BOLD}Lab FTP/FTPS amb SFTPGo + Containerlab${NC}"
    echo ""
    echo -e "  ${CYAN}Ús:${NC} $0 <comanda> [args]"
    echo ""
    echo -e "  ${BOLD}Comandes principals:${NC}"
    echo -e "    ${GREEN}check${NC}              Comprova els prerequisits"
    echo -e "    ${GREEN}build [imatge]${NC}     Construeix imatges Docker (switch, client-lftp, client-rclone, web-nginx, web-angie, proxy, all)"
    echo -e "    ${GREEN}deploy <N>${NC}         Desplega el laboratori (etapa 1-6)"
    echo -e "    ${GREEN}destroy${NC}            Destrueix el laboratori"
    echo -e "    ${GREEN}status${NC}             Mostra l'estat del lab"
    echo -e "    ${GREEN}certs${NC}              Genera certificats TLS amb mkcert (etapa 2+)"
    echo ""
    echo -e "  ${BOLD}Utilitats:${NC}"
    echo -e "    ${GREEN}shell [node]${NC}       Entra al shell d'un node (default: client)"
    echo -e "    ${GREEN}logs  [node]${NC}       Mostra els logs d'un node (default: server)"
    echo ""
    echo -e "  ${BOLD}Etapes disponibles:${NC}"
    echo -e "    ${CYAN}1${NC}  FTP sense xifrat (bàsic)"
    echo -e "    ${CYAN}2${NC}  FTPES (explicit TLS) + FTPS (implicit TLS)"
    echo -e "    ${CYAN}3${NC}  FTPS + S3 backend (MinIO)"
    echo -e "    ${CYAN}4${NC}  FTPS + Keycloak OIDC"
    echo -e "    ${CYAN}5${NC}  Clients textuals (lftp + rclone)"
    echo -e "    ${CYAN}6${NC}  Proxy invers (nginx + Angie)"
    echo ""
    echo -e "  ${BOLD}Imatges:${NC}"
    echo -e "    Oficials: ${CYAN}drakkan/sftpgo${NC} (server), ${CYAN}linuxserver/filezilla${NC} (client)"
    echo -e "    Custom:   ${CYAN}switch, client-lftp, client-rclone, web-nginx, web-angie, proxy${NC}"
    echo ""
    echo -e "  ${BOLD}Exemples:${NC}"
    echo -e "    $0 deploy 1                     # Desplega l'etapa 1 (FTP bàsic)"
    echo -e "    $0 certs && $0 deploy 2          # Genera certs i desplega l'etapa 2"
    echo -e "    $0 destroy                       # Destrueix el lab actual"
    echo -e "    $0 shell server                  # Shell al servidor SFTPGo"
    echo -e "    $0 build switch                  # Reconstrueix només la imatge switch"
    echo ""
}

# ─── Dispatcher ──────────────────────────────────────────────────────────────
CMD="${1:-help}"
shift || true

case "$CMD" in
    check)   check_deps ;;
    build)   build "${1:-all}" ;;
    deploy)  deploy "${1:-}" ;;
    destroy) destroy ;;
    status)  status ;;
    certs)   certs ;;
    shell)   shell "${1:-client}" ;;
    logs)    logs "${1:-server}" ;;
    help|--help|-h) usage ;;
    *) warn "Comanda desconeguda: $CMD"; usage; exit 1 ;;
esac
