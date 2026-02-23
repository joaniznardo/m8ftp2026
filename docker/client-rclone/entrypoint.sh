#!/bin/bash
# ─── entrypoint.sh per al contenidor client-rclone ───────────────────────────
# El contenidor arranca i espera fins que containerlab crida exec:
# que configurarà la xarxa via l'init script bind-muntat (init-client-rclone.sh).
set -e
exec tail -f /dev/null
