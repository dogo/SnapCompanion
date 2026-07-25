# Live opponent tracking (native)

A working, fully native live Marvel Snap opponent overlay.

## Pipeline

1. **`NETransparentProxyProvider` system extension** (`Sources/SnapCompanionProxy`)
   intercepts only the SNAP process (Developer ID + `app-proxy-provider-systemextension`
   entitlement + provisioning profiles, notarized; the app installs a bundled dev CA).
2. **Per-flow TLS MITM**: it peeks the ClientHello SNI, and for the realtime
   `*-ws-cf.nvprod.snapgametech.com` WebSocket terminates TLS with a bundled leaf
   (NIOSSL over an EmbeddedChannel) and relays to the real server (NWConnection);
   every other flow passes through untouched so the game keeps working.
3. **`WebSocketFrameParser` + `MatchTracker`** read `GetChangesResponse` changes into
   a match snapshot (opponent name, revealed cards, locations, turn) written to
   `/tmp/snapcompanion-live-match.json`.
4. **App** polls the file and renders a floating overlay: opponent name, **bot flag**
   (MarvelSnap.pro `getbots`), turn, hexagon **locations**, revealed cards, and a
   **deck prediction** with confidence (`DeckPredictor` + MarvelSnap.pro `getmeta`).

## Cube value, snaps, and match result

These come from two sources the app already has, not the HTTP/2 API host:

- **Cube value + snap count** ride the same realtime WebSocket. `MatchTracker`
  reads `GameCreateChange.StartingCubeValue` and each `GameStakesRaisedChange`
  (`CubeValue` / `TotalRaisedCount`) into the snapshot.
- **Match result** (won/lost, cubes at stake) is in the local `GameState.json`
  (`ClientResultMessage.GameResultAccountItems`, matched by the client's own
  `AccountId`); `MatchState` reads it once the match ends.

The HTTP/2 API host (`*-cf.nvprod.snapgametech.com`) is **certificate-pinned**:
the game rejects our leaf and reconnect-storms, so it's left as passthrough. An
early attempt to MITM it as HTTP/2 confirmed the storm and read nothing.

## ponytail / TODO

Dev CA + leaf are bundled (a shipped build must generate a unique CA per install
so the private key isn't extractable). Kept on a branch so main's 1.0 stays clean.
