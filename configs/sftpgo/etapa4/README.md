# ─── Etapa 4: OAuth2/OIDC amb Keycloak ────────────────────────────────────────
# Autenticació federada per a SFTPGo via Keycloak
#
# ESTAT: Pendent de desenvolupament complet
# PREREQUISIT: Etapes 1, 2 i 3 completades
#
# Components afegits:
#   - Contenidor keycloak (10.50.0.40)
#   - Realm "lab" amb client "sftpgo"
#   - Usuaris del laboratori gestionats des de Keycloak
#   - SFTPGo configurat amb external_auth_hook → OIDC
#
# Flux d'autenticació:
#   Client FTP → SFTPGo → Keycloak (OIDC token) → Autoritzat/Denegat
#
# Topologia ampliada:
#
#   [client] ─── [switch-lan] ─── [router-frr] ─── (WAN)
#   [server] ──────────────────┘
#   [coredns] ─────────────────┘
#   [rustfs]  ─────────────────┘
#   [keycloak] ────────────────┘   ← NOU a l'Etapa 4
#
# Keycloak:
#   URL:      http://keycloak.test:8180
#   Admin:    admin / admin
#   Realm:    lab
#   Client:   sftpgo (confidential)
#
# Vegeu etapa4/instruccions-etapa4.md per als passos detallats.

echo "Etapa 4: Keycloak OAuth2/OIDC - Llegiu configs/sftpgo/etapa4/README.md"
