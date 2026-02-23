#!/bin/bash
# ─── entrypoint.sh per al contenidor proxy (nginx proxy invers) ──────────────
# El contenidor arranca i espera fins que containerlab crida exec:
# que configurarà la xarxa i el proxy nginx via l'init script bind-muntat.
set -e
exec tail -f /dev/null
