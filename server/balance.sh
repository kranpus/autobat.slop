#!/usr/bin/env bash
# Balance simulator on the Docker server (VPS / Hostinger): fights many
# battles with the real battle code and reports how each unit does.
#
#   server/balance.sh                          400 random army pairings (~800 battles)
#   server/balance.sh --battles=2000           more battles, narrower error bars
#   server/balance.sh --minutes=30             run for about 30 minutes
#   server/balance.sh --mode=duels             every unit vs every unit, one squad each
#   server/balance.sh --mode=calibrate         win rate by power ratio (Strength check)
#   server/balance.sh --power=1500 --rating=1800 --trinkets
#
# All options are listed at the top of tools/balance_sim.gd. It runs inside
# the server container at low CPU priority, so the live game stays smooth, on
# half the CPU cores (--threads=N to change). The report is printed and saved,
# with CSV spreadsheets, to ./balance-results/ on the VPS.
set -uo pipefail
CONTAINER="${ADMIN_CONTAINER:-legion-draft-server}"
DIR='/home/godot/.local/share/godot/app_userdata/Autobat Legions/balance'

if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true; then
  echo "The server container '$CONTAINER' isn't running."
  echo "Start it with: docker compose -f server/docker-compose.vps.yml up -d"
  exit 1
fi

TTY=""
[ -t 1 ] && TTY="-t"
docker exec $TTY "$CONTAINER" nice -n 15 godot --headless --path /game -s res://tools/balance_sim.gd -- "$@"
status=$?
mkdir -p balance-results
if docker cp "$CONTAINER:$DIR/." balance-results/ >/dev/null 2>&1; then
  echo "Reports and spreadsheets copied to $(pwd)/balance-results/"
fi
exit $status
