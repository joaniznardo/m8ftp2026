#!/bin/bash
# ─── entrypoint.sh per al contenidor client-lftp ─────────────────────────────
# El contenidor arranca i espera fins que containerlab crida exec:
# que configurarà la xarxa via l'init script bind-muntat (init-client-lftp.sh).
set -e
exec tail -f /dev/null
