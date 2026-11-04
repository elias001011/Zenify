# Zenify sync peer

A Zenify device with no screen. It takes part in Local Sync the way any
device does, keeps what the others sync and gives it back, so a phone and a
computer that are never on at the same time still end up with the same
library. It runs on a server that is always on, on the same network (Local
Sync finds devices by broadcast on the local network; it does not work over
the internet).

It changes nothing in the app: it speaks the app's own protocol. The sync
document, the encryption and the pairing are the app's own code
(`lib/services/local_sync`, shared by link, so a change there reaches the
peer when it is copied again); the server half (the routes and the checks of
each request) is a copy of the app's, and `test/local_sync/sync_peer_protocol_test.dart`
keeps its constants equal to the app's.

```
dart run bin/zenify_sync_peer.dart [--data DIR] [--name NAME] [--port PORT]
                                   [--read-timeout SECONDS]
```

It keeps only the sync document (what was liked, the playlists, the history
and so on, with the clocks the merge needs), not a copy of the app.

## Pairing

The peer runs all the time and nobody watches it, so it does not accept a
pairing by itself: open it first.

1. `run.sh pair` opens pairing for 5 minutes, for one attempt (a wrong PIN
   closes it again).
2. Pair from the app as with any device (Settings → Local Sync → the peer
   shows up in the list).
3. The PIN is not on a screen: `run.sh pin` shows it (it is also in the log),
   for 60 seconds. Type it in the app.

Pair each of your devices once; after that they sync with the peer
automatically. `run.sh devices` lists the paired devices and `run.sh unpair
ID` removes one (a lost phone, for example): it stops the peer, edits who is
paired and starts it again.

## On a Termux server

```
pkg install dart
mkdir -p ~/zenify-sync/app
# from this repository, with the links resolved:
tar -C tools/sync_peer -chf - bin pubspec.yaml lib | ssh HOST 'tar -C ~/zenify-sync/app -xf -'
scp tools/sync_peer/run.sh HOST:zenify-sync/run.sh
ssh HOST 'cd ~/zenify-sync/app && dart pub get && ~/zenify-sync/run.sh start'
```

`run.sh start | stop | status | log | pair | pin | devices | unpair ID`. To start it with the server, call
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

## What it refuses

Before it knows who sent a request it reads little: a request needs
`Content-Type: application/json`; a merge needs a `Content-Length` (the apps
always send one) of at most 64 MB, and only one such body is read at a time (a
second one gets 429); a body that takes longer than `--read-timeout` (45
seconds) to arrive is dropped. The JSON of a merge is decoded on another
isolate.

## Limits

- Only on the local network (broadcast discovery).
- One merge at a time; the whole document is kept in memory.
- The peer has no screen to show what was changed, so it reports changes to
  the app only as metadata.
