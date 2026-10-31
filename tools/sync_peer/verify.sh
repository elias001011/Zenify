#!/usr/bin/env bash
# Checks a peer with two devices that use the app's own sync code: device A
# sends a liked song; device B, another device that starts empty, pairs with
# the peer and receives it.
#
#   tools/sync_peer/verify.sh           starts a peer on this machine and checks it
#   tools/sync_peer/verify.sh ssh://USER@HOST:PORT[/DATA]
#       checks the peer running on a server on the local network; the PIN it
#       shows for each pairing is read from its data folder over ssh.
set -euo pipefail
cd "$(dirname "$0")/../.."
work="$(mktemp -d)"
name='Zenify Sync Server'
peer_pid=''
cleanup() {
  [ -n "$peer_pid" ] && kill "$peer_pid" 2>/dev/null || true
  [ -n "${pin_pid:-}" ] && kill "$pin_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

if [ -n "${1:-}" ]; then
  target="${1#ssh://}"; host="${target%%/*}"; user_host="${host%%:*}"; port="${host##*:}"
  data="${target#*/}"; [ "$data" = "$target" ] && data='zenify-sync/data'
  # Copy the PIN the server shows to a local file as it appears.
  ( while true; do
      ssh -o BatchMode=yes ${SSH_OPTS:-} -p "$port" "$user_host" "cat $data/pairing-pin.txt" \
        >"$work/pin.tmp" 2>/dev/null && mv "$work/pin.tmp" "$work/pin.txt" || rm -f "$work/pin.txt"
      sleep 0.3
    done ) &
  pin_pid=$!
  pin_file="$work/pin.txt"
else
  (cd tools/sync_peer && dart pub get >/dev/null)
  dart run tools/sync_peer/bin/zenify_sync_peer.dart --data "$work/peer" --name "$name" \
    >"$work/peer.log" 2>&1 &
  peer_pid=$!
  for _ in $(seq 1 60); do grep -q 'on port' "$work/peer.log" 2>/dev/null && break; sleep 0.5; done
  pin_file="$work/peer/pairing-pin.txt"
fi

for role in a b; do
  MUSIFY_HEADLESS_ROLE="$role" MUSIFY_HEADLESS_PIN_FILE="$pin_file" \
    MUSIFY_HEADLESS_DATA="$work/device-$role" MUSIFY_HEADLESS_NAME="$name" \
    flutter test --no-pub test/local_sync/support/headless_device_test.dart
done
echo "OK: device B received what device A sent through the peer"
