# Zenify sync peer

A Zenify device with no screen. It takes part in Local Sync the way any
device does, keeps what the others sync and gives it back, so a phone and a
computer that are never on at the same time still end up with the same
library. It runs on a server that is always on, on the same network (Local
Sync finds devices by broadcast on the local network; it does not work over
the internet).

It changes nothing in the app: it speaks the app's own protocol with the
app's own code (`lib/services/local_sync`, shared by link, so a change to the
protocol in the app reaches the peer when it is copied again).

```
dart run bin/zenify_sync_peer.dart [--data DIR] [--name NAME] [--port PORT]
```

It keeps only the sync document (what was liked, the playlists, the history
and so on, with the clocks the merge needs), not a copy of the app.

## Pairing

Start the peer, then pair from the app as with any device (Settings → Local
Sync → the peer shows up in the list). The PIN is not on a screen: it is
printed in the peer's output and written to `pairing-pin.txt` in its data
folder for 60 seconds. Read it, type it in the app. Pair each of your devices
once; after that they sync with the peer automatically.

## On a Termux server

```
pkg install dart
mkdir -p ~/zenify-sync/app
# from this repository, with the links resolved:
tar -C tools/sync_peer -chf - bin pubspec.yaml lib | ssh HOST 'tar -C ~/zenify-sync/app -xf -'
scp tools/sync_peer/run.sh HOST:zenify-sync/run.sh
ssh HOST 'cd ~/zenify-sync/app && dart pub get && ~/zenify-sync/run.sh start'
```

`run.sh start | stop | status | log | pin`. To start it with the server, call
`~/zenify-sync/run.sh start` where the server starts its services.

## Checking it

`verify.sh` pairs two devices that use the app's own sync code with a peer and
checks that what one sends the other receives:

```
tools/sync_peer/verify.sh                       # a peer started on this machine
SSH_OPTS="-i KEY" tools/sync_peer/verify.sh ssh://USER@HOST:PORT/zenify-sync/data
```

Against a real server it leaves two test pairings and a test liked song in
the peer: stop it and delete its `data` folder afterwards.

## Limits

- Only on the local network (broadcast discovery).
- One merge at a time; the whole document is kept in memory.
- The peer has no screen to show what was changed, so it reports changes to
  the app only as metadata.
