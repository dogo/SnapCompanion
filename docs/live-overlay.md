# Live opponent tracking (architecture)

How the native live Marvel Snap opponent overlay works, end to end.

## Pipeline

1. **`NETransparentProxyProvider` system extension** (`Sources/SnapCompanionProxy`)
   intercepts only the SNAP process (Developer ID + `app-proxy-provider-systemextension`
   entitlement + provisioning profiles, notarized).
2. **Per-flow TLS MITM**: it peeks the ClientHello SNI, and for the realtime
   `*-ws-cf.nvprod.snapgametech.com` WebSocket terminates TLS with a per-install
   leaf (NIOSSL over an EmbeddedChannel) and relays to the real server
   (NWConnection); every other flow passes through untouched so the game keeps
   working. See [Certificates](#certificates) for how the leaf/CA are generated.
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

## Certificates

`CertificateStore` generates a **unique CA + leaf per install** (swift-certificates)
on the extension's first run; the CA private key is discarded right after signing
the one leaf, and the leaf key + chain live 0600 in the extension's container. The
CA cert is copied to `/tmp/snapcompanion-ca.pem` for the app to trust (see below).

## Trusting the CA

The extension is sandboxed and can't touch the trust store; the admin/system
domain needs root. So the **app** (`CATrust`, running as the user) adds the CA to
the **user** trust domain with an in-process `SecTrustSettingsSetTrustSettings`
call — one login-keychain prompt, no `sudo`. The game runs as the same user and
honors user-domain trust. Triggered on enable and from a menu item.
