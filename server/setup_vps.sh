#!/usr/bin/env bash
# One-time setup of a fresh Ubuntu VPS (e.g. Hostinger KVM) for Autobat Legions.
# Run as root from the game folder:   server/setup_vps.sh play.yourgame.com
# Installs Docker if needed, opens the firewall ports, saves your domain and
# starts the game server and the browser version. Safe to run again.
set -euo pipefail
DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  echo "Usage: server/setup_vps.sh <your domain, e.g. play.yourgame.com>"
  exit 1
fi
cd "$(dirname "$0")/.."

if ! command -v docker >/dev/null 2>&1; then
  echo "== Installing Docker"
  curl -fsSL https://get.docker.com | sh
fi

if command -v ufw >/dev/null 2>&1; then
  echo "== Opening firewall ports"
  ufw allow 22/tcp >/dev/null          # keep SSH working
  ufw allow 80/tcp >/dev/null          # web page + certificate checks
  ufw allow 443/tcp >/dev/null         # web page (HTTPS)
  ufw allow 24704/tcp >/dev/null       # browser game (wss)
  ufw allow 24702:24703/udp >/dev/null # game app
  ufw --force enable >/dev/null
fi

echo "DOMAIN=$DOMAIN" > server/.env

# The domain must point at this server before Caddy can get a certificate.
MY_IPS="$(hostname -I 2>/dev/null || true)"
DNS_IP="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR==1{print $1}')"
if [ -z "$DNS_IP" ]; then
  echo "WARNING: $DOMAIN doesn't resolve yet. Add an A record pointing to this server"
  echo "         ($MY_IPS) and run this script again once it does."
elif ! echo " $MY_IPS " | grep -q " $DNS_IP "; then
  echo "WARNING: $DOMAIN points to $DNS_IP, but this server is $MY_IPS."
  echo "         Fix the A record first, or the HTTPS certificate can't be issued."
fi

echo "== Building and starting (the first build takes a few minutes)"
docker compose -f server/docker-compose.vps.yml up -d --build

echo
echo "Done."
echo "  Browser version:  https://$DOMAIN"
echo "  Game app server:  $DOMAIN  (UDP 24702)"
echo "  Admin console:    docker attach legion-draft-server   (leave with Ctrl+P, Ctrl+Q)"
echo "  Logs:             docker compose -f server/docker-compose.vps.yml logs -f"
