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

## What lives where the WebSocket can't reach

The cube value, snap events, and match result (cubes won/lost) are on the game's
**HTTP/2 API** channel, not the WebSocket. MITMing that host causes a reconnect
storm and would need a full HTTP/2 MITM — out of scope, so those are dropped.

## ponytail / TODO

Dev CA + leaf are bundled (a shipped build must generate a unique CA per install
so the private key isn't extractable). Kept on a branch so main's 1.0 stays clean.
