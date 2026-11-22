#!/usr/bin/env bash
# Admin console for the Docker server (VPS / Hostinger), without attaching.
#
#   server/admin.sh status                    run one command and show the reply
#   server/admin.sh "gold battle 1.5"
#   server/admin.sh                           interactive: type commands, 'exit' to leave
#
# Type 'help' for the list of commands. Safe to use in Hostinger's browser
# terminal: nothing to detach from, and Ctrl+C only leaves this script.
set -uo pipefail
CONTAINER="${ADMIN_CONTAINER:-legion-draft-server}"
DIR='$HOME/.local/share/godot/app_userdata/Autobat Legions/admin'

if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true; then
  echo "The server container '$CONTAINER' isn't running."
  echo "Start it with: docker compose -f server/docker-compose.vps.yml up -d"
  exit 1
fi

run() {
  local cmd="$*" id
  id="$(date +%s%N)$RANDOM"
  # Hand the command to the server (it checks twice a second).
  docker exec -i "$CONTAINER" sh -c "d=\"$DIR\"; mkdir -p \"\$d\"; cat >> \"\$d/commands.txt\"" <<< "$id	$cmd"
  # Wait for the reply (up to ~10 s).
  for _ in $(seq 1 40); do
    sleep 0.25
    # One read: the reply counts only once its end marker is there too.
    local reply
    if reply="$(docker exec "$CONTAINER" sh -c "d=\"$DIR\"; [ -f \"\$d/replies.txt\" ] && awk -v id='$id' '\$0==\"### end \"id{done=1;exit} on{print} \$0==\"### \"id{on=1} END{exit !done}' \"\$d/replies.txt\"")"; then
      printf '%s\n' "$reply"
      return 0
    fi
  done
  echo "(No reply from the server. Is it running? See: docker logs --tail 20 $CONTAINER)"
  return 1
}

if [ $# -gt 0 ]; then
  run "$@"
  exit $?
fi

echo "Autobat Legions admin console ($CONTAINER). Type 'help' for commands, 'exit' to leave."
while IFS= read -r -e -p "admin> " line; do
  case "$line" in
    "") continue ;;
    exit|quit) break ;;
    *) run "$line" ;;
  esac
done
