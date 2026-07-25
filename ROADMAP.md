# SnapSync Roadmap

A native macOS app that locates local Marvel Snap data, generates a normalized snapshot, and synchronizes it with MarvelSnap.pro.

## Status

- ✅ Completed
- 🚧 Partial or in progress
- ⬜ Not started

## Current state

### ✅ Completed

- Swift Package compatible with Swift 6.2+ and macOS 13+.
- Dependency-free `snapsync` executable.
- Automatic discovery of `States/nvprod` inside macOS containers.
- Validation that `CollectionState.json` is present.
- Manual path support through `--path`.
- Reading of `ProfileState.json` and `CollectionState.json`.
- Stable reads with up to three attempts when the file size, modification date, or inode changes during copying.
- Extraction and normalization of:
  - account and player name;
  - cards grouped by definition;
  - variants for each card;
  - decks and their cards.
- Export is blocked when the minimum schema is not recognized.
- Sorted JSON export with atomic writes.
- Available commands:

  ```bash
  snapsync discover
  snapsync inspect [--path <nvprod>]
  snapsync export [--path <nvprod>] --output <file>
  snapsync connect [--path <nvprod>]
  snapsync sync [--path <nvprod>] (--dry-run | --confirm)
  snapsync watch [--path <nvprod>] --confirm
  snapsync doctor [--path <nvprod>]
  ```

- End-to-end Swift Testing coverage for discovery, parsing, and export.
- Successful validation against a real local Marvel Snap installation.
- Current MarvelSnap.pro contract confirmed against the official tracker.
- Compatible payloads for the `Decks` and `Collection` events.
- `sync --dry-run` displays the endpoint and summary without making a request.
- Account-linking flow implemented through `connect`.
- Token stored in Keychain only after confirmed association.
- Real account link validated with an `OK` response from MarvelSnap.pro.
- Manual upload implemented with mandatory confirmation.
- Token validated before upload; gzip+Base64 body compatible with the tracker.
- Real upload validated with an `ok` response.
- Canonical SHA-256 hash and atomic checkpoint after each successful upload.
- Identical uploads are skipped before accessing Keychain or the network.
- Native `nvprod` monitoring with a 600 ms debounce and serialized uploads.
- Retry for transient failures with backoff, cancellation, and `Retry-After` support in seconds or HTTP-date format.
- Atomic, private (`0600`) latest-wins outbox cleared only after a successful checkpoint.
- Tuist-generated native Xcode app target with dashboard, local data, and manual synchronization.
- Synchronization coordinator shared between the CLI and app.
- Manual selection through `NSOpenPanel` with a private (`0600`), read-only security-scoped bookmark.
- `MenuBarExtra` sharing dashboard state and synchronization.
- In-app account linking with browser confirmation and Keychain token storage.
- Automatic monitoring and synchronization inside the app with a persistent preference.
- Versioned privacy policy and an in-dashboard privacy summary.
- `snapsync doctor` checks the local environment without exposing paths, accounts, decks, or tokens.
- Native discovery, parsing, and synchronization logs through `OSLog`, without private data.
- Reproducible `SnapSync.app` bundle with an icon, localized resources, and configurable signing.
- Compressed and validated DMG containing the app and an `/Applications` shortcut.
- Fastlane/Match Developer ID and notarization pipeline without repository credentials.
- App ID and Developer ID certificate created; certificate installed and stored encrypted in the Match repository.
- App and DMG signed with Developer ID and validated locally.
- First DMG notarized, stapled, and accepted by Gatekeeper.
- `0.9.0` DMG smoke-tested for installation, launch, discovery, and idempotent synchronization.
- Sanitized fixtures and an explicit V1 schema fingerprint shared by parsing and upload.
- Lightweight private history of the latest collection or deck change, without a database.
- Local inventory with collection level, credits, gold, tokens, and boosters.
- Bundle promoted to `1.0.0`.
- In-app account disconnection and confirmed local data cleanup.

### ⬜ Not started

- Automatic updates.
- Unique per-install CA and automated certificate trust for the overlay.

## Roadmap

### 0.1 — Discovery CLI ✅

- Discover the real Marvel Snap directory.
- Inspect the available files.
- Accept `--path` as a manual fallback.

### 0.2 — Local snapshot ✅

- Parse the account, collection, and decks. ✅
- Generate a normalized snapshot. ✅
- Export JSON. ✅
- Add sanitized fixtures based on real schemas. ✅
- Explicitly version known schemas. ✅
- Boosters and inventory are read locally but are not part of the current upload contract.

### 0.3 — MarvelSnap.pro contract ✅

- Endpoint: `POST /snap/donew2.php?cmd=cm_uploadpackfile&version=<version>m`.
- Transport: a gzipped, Base64-encoded JSON array.
- Current events: `Decks` and `Collection`, containing the raw game arrays.
- `uid`: local Snap account ID; `time`: `0`.
- `sync --dry-run` implemented without sending data.
- Contract test without live network access.

### 0.4 — Manual synchronization ✅

- Link the account through `tokenrequest`, `tokencheck`, and `setuserdata`. ✅
- Store the token in Keychain. ✅
- Manually validate account linking with a real account. ✅
- Upload the snapshot only under an explicit command. ✅
- Handle responses and errors without logging private data. ✅
- Validate a real upload and its confirmation on the website. ✅
- Prevent duplicate uploads using a hash and the last successful checkpoint. ✅

### 0.5 — Automatic synchronization ✅

- Read files stably while the game updates them. ✅
- Monitor directory changes. ✅
- Apply debounce. ✅
- Retry only recoverable failures. ✅
- Preserve the latest snapshot in a local outbox. ✅

### 0.6 — macOS app ✅

- Create a SwiftUI app using the existing core. ✅
- Add folder selection with `NSOpenPanel`. ✅
- Persist access with a security-scoped bookmark when needed. ✅
- Implement the dashboard and manual synchronization. ✅
- Implement the menu bar interface. ✅
- Implement account setup. ✅
- Enable automatic monitoring and synchronization inside the app. ✅
- Document privacy in the app and repository. ✅
- Allow the app to remove the token from Keychain. ✅
- Allow the app to clear the bookmark, history, checkpoint, and outbox. ✅

### 0.7 — Diagnostics and distribution ✅

- Implement `snapsync doctor` and a sanitized report. ✅
- Add privacy-aware logs with `OSLog`. ✅
- Generate an `.app` bundle with an icon and ad hoc signature. ✅
- Create the App ID and Developer ID through Match. ✅
- Sign the app and DMG with Developer ID. ✅
- Notarize, staple the ticket, and validate with Gatekeeper. ✅
- Generate the DMG. ✅
- Install and run a local smoke test of the `0.9.0` DMG. ✅
- Migrate old private files to `0600` permissions when they are read. ✅
- Evaluate Sparkle only when recurring public distribution exists.

### 0.8 — Lightweight history ✅

- Store only the latest relevant snapshot and latest diff. ✅
- Detect new cards, variants, and deck changes. ✅
- Persist private JSON (`0600`) without SQLite. ✅
- Preserve the latest diff when only resources or boosters change. ✅

### 0.9 — Inventory and resources ✅

- Read the collection level. ✅
- Read credits, gold, Collector's Tokens, and Wild Boosters. ✅
- Read per-card boosters and display the total. ✅
- Display inventory in the app and the `inspect` command. ✅
- Keep inventory and history exclusively local. ✅

### 1.0 — Stable collection and decks ✅

Criteria:

- automatic discovery and a persistent manual fallback; ✅
- versioned known schemas, with uploads blocked for incompatible schemas; ✅
- export plus manual and automatic synchronization; ✅
- idempotency and offline recovery; ✅
- native sidebar interface with dedicated overview and settings screens; ✅
- searchable local collection browser with filters, sorting, and cached artwork; ✅
- deck browser with card contents and per-card details; ✅
- usable diagnostics; ✅
- signed and notarized distribution with documented privacy. ✅

### 1.1 — Live opponent overlay ✅

- Native `NETransparentProxyProvider` system extension intercepting only the Marvel Snap process. ✅
- Per-flow TLS MITM of the realtime game WebSocket (NIOSSL), with passthrough for every other flow. ✅
- Live match tracking: opponent name, revealed cards, locations, and turn. ✅
- Bot detection via MarvelSnap.pro's known-AI lists. ✅
- Opponent deck prediction from MarvelSnap.pro archetypes, with a confidence score and top candidates. ✅
- Live cube value and snap count from the WebSocket, and win/loss result (cubes won/lost) from local `GameState.json`. ✅
- Floating SwiftUI overlay, localized in English and Brazilian Portuguese. ✅
- Bundle promoted to `1.1.0`.

## Next step

Run the final signed and notarized DMG smoke test for `1.1.0`.

## Post-1.1

Add only when supported by proven demand:

- per-deck session stats aggregated from `GameState.json` match results;
- complete SQLite history, only if lightweight history becomes insufficient;
- multiple destinations;
- deck recommendations.
