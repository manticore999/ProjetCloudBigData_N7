#!/usr/bin/env bash
# Sous Windows, les fichiers montés depuis l'hôte apparaissent en 0777 et
# OpenSSH refuse une clé privée trop ouverte : on la recopie en 0600.
set -euo pipefail

if [ -f /work/.secrets/id_ed25519 ]; then
  install -d -m 700 /root/.ssh
  install -m 600 /work/.secrets/id_ed25519 /root/.ssh/cluster_key
fi

exec "$@"
