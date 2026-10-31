#!/data/data/com.termux/files/usr/bin/bash
# Starts, stops and checks the Zenify sync peer on a Termux server.
#   run.sh start | stop | status | log | pair | pin | devices | unpair ID
here="$(cd "$(dirname "$0")" && pwd)"
data="$here/data"
pidfile="$here/peer.pid"
logfile="$here/peer.log"

running() { [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; }

# The commands that read or change who is paired run with the peer stopped.
offline() {
  local was_running=false
  running && was_running=true && "$0" stop >/dev/null
  (cd "$here/app" && dart run bin/zenify_sync_peer.dart --data "$data" "$@")
  $was_running && "$0" start >/dev/null
  return 0
}

case "${1:-}" in
  start)
    if running; then echo "already running ($(cat "$pidfile"))"; exit 0; fi
    command -v termux-wake-lock >/dev/null && termux-wake-lock
    cd "$here/app"
    nohup dart run bin/zenify_sync_peer.dart --data "$data" >>"$logfile" 2>&1 &
    echo $! >"$pidfile"
    echo "started ($(cat "$pidfile"))"
    ;;
  stop)
    if running; then kill "$(cat "$pidfile")"; rm -f "$pidfile"; echo stopped; else echo "not running"; fi
    ;;
  status)
    if running; then echo "RUNNING ($(cat "$pidfile"))"; else echo "STOPPED"; fi
    ;;
  log) tail -n "${2:-30}" "$logfile" ;;
  pair)
    touch "$data/pairing-open"
    echo "Pairing is open for 5 minutes, for one attempt. Pair from the app, then: $0 pin"
    ;;
  pin) cat "$data/pairing-pin.txt" 2>/dev/null || echo "no pairing under way" ;;
  devices) offline --list ;;
  unpair) offline --unpair "${2:?usage: $0 unpair ID}" ;;
  *) echo "Usage: $0 {start|stop|status|log|pair|pin|devices|unpair ID}" ;;
esac
