#!/bin/bash
# ─── entrypoint.sh per al contenidor web-nginx (web01/web02) ─────────────────
# El contenidor arranca i espera fins que containerlab crida exec:
# que configurarà la xarxa i nginx via l'init script bind-muntat.
set -e
exec tail -f /dev/null
