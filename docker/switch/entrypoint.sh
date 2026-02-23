#!/bin/bash
# ─── entrypoint.sh per al contenidor switch (Linux bridge) ───────────────────
# El contenidor arranca i espera fins que containerlab crida exec:
# que configurarà el bridge via l'init script bind-muntat (init-bridge.sh).
set -e
exec tail -f /dev/null
