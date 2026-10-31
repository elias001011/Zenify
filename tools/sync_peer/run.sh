#!/data/data/com.termux/files/usr/bin/bash
# Starts, stops and checks the Zenify sync peer on a Termux server.
#   run.sh start | stop | status | log | pin
here="$(cd "$(dirname "$0")" && pwd)"
data="$here/data"
pidfile="$here/peer.pid"
logfile="$here/peer.log"

running() { [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; }

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
  pin) cat "$data/pairing-pin.txt" 2>/dev/null || echo "no pairing under way" ;;
  *) echo "Usage: $0 {start|stop|status|log|pin}" ;;
esac
