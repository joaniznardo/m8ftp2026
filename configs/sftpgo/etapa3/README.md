# ─── Etapa 3: RustFS com a storage extern per a SFTPGo ────────────────────────
# Aquesta etapa configura un bucket S3-compatible (RustFS) com a backend
# d'emmagatzematge per a SFTPGo.
#
# ESTAT: Pendents de desenvolupament complet
# PREREQUISIT: Etapa 2 completada (certificats mkcert ja existents)
#
# Components afegits:
#   - Contenidor rustfs (10.50.0.30) amb S3 API compatible
#   - Actualització de sftpgo.json per usar virtual filesystem S3
#   - Topologia dedicada: topologies/etapa3.yml (rustfs i el link ja inclosos)
#
# Topologia ampliada:
#
#   [client] ─── [switch-lan] ─── [router-frr] ─── (WAN)
#   [server] ──────────────────┘
#   [coredns] ─────────────────┘
#   [rustfs]  ─────────────────┘   ← NOU a l'Etapa 3
#
# Configuració del bucket RustFS:
#   Endpoint: http://rustfs.test:9000
#   Bucket:   sftpgo-data
#   Accés:    rustfs-access-key / rustfs-secret-key
#
# Vegeu etapa3/instruccions-etapa3.md per als passos detallats.

