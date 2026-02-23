#!/bin/bash
# ─── entrypoint.sh per al contenidor web-angie (web03) ───────────────────────
# El contenidor arranca i espera fins que containerlab crida exec:
# que configurarà la xarxa i Angie via l'init script bind-muntat.
set -e
exec tail -f /dev/null
