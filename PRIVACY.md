# SnapSync Privacy Policy

Last updated: July 25, 2026.

SnapSync does not use analytics, telemetry, advertising, or collect data of its own.

## Data read locally

The app locates, or uses a folder you select, and reads the Marvel Snap `ProfileState.json` and `CollectionState.json` files without modifying them. It extracts:

- account ID and name;
- collection and variants;
- decks, deck names, and cards;
- collection level, currencies, and card boosters.

The folder path and complete source files are not uploaded.

## Data sent to MarvelSnap.pro

When linking an account, SnapSync sends the account name, account ID, and time zone offset to MarvelSnap.pro. When synchronizing, it sends:

- account ID;
- collection and variants;
- decks, deck names, and cards;
- the authentication token required to validate the account.

Outside the account-linking flow described above, no synchronization data is sent until the account is linked. Automatic synchronization can be disabled from the dashboard or the app menu.

The collection browser requests card artwork from `static.marvelsnap.pro` using the public card definition ID in the image URL. These requests do not include the Snap account ID or MarvelSnap.pro token. As with any web request, the CDN receives standard network metadata such as the IP address and user agent.

The collection browser also requests the public Marvel Snap card catalog from the read-only DotGG API. This request does not include account, collection, deck, path, or authentication data. The result is reduced to card IDs and names and cached locally for 24 hours.

## Live opponent overlay

The optional live overlay uses a bundled system extension that intercepts only the Marvel Snap process's network traffic, on your Mac. For the game's realtime WebSocket it terminates and re-originates TLS locally to read the current match, and forwards the traffic to the game's servers unchanged — nothing about the match leaves your machine.

From that connection it reads the opponent's name, revealed cards, the locations, the turn, the cube value, and snaps. The end-of-match result (win or loss and the cubes) is read from the local `GameState.json`. These values are shown in the overlay and, grouped by deck, aggregated into session statistics kept only in memory for the current app session.

To intercept the game's TLS, the extension generates a unique certificate authority and leaf for this install on first use. The private keys stay on your Mac — the CA key is discarded right after signing the leaf — and nothing secret is bundled with the app. The app trusts the generated CA in your user trust domain; the rest of your system trust settings are untouched.

The overlay loads opponent card and location artwork from `static.marvelsnap.pro` and requests MarvelSnap.pro's public known-AI list and archetype metadata to flag likely bots and predict the opponent's deck. These requests use public identifiers only and do not include your account, the opponent's identity, or match data.

## Data stored on your Mac

- The MarvelSnap.pro token is stored in Keychain under the `com.snapsync.marvelsnappro` service.
- Access to the selected folder is stored as a read-only security-scoped bookmark.
- The local checkpoint contains the snapshot hash, timestamp, and account ID.
- The lightweight history stores the latest normalized snapshot and the latest collection or deck change.
- If an upload fails, the outbox retains only the latest pending snapshot until synchronization succeeds.
- The bookmark, checkpoint, history, and outbox use local `0600` permissions.
- Logs do not include the token, folder path, account, collection, or deck names.
- Card artwork is cached by Kingfisher in the standard app cache and can be removed by clearing the app's macOS cache.
- The public card catalog cache contains only card IDs, names, and its refresh date.

These files are stored in `~/Library/Application Support/SnapSync`. They can be removed from the dashboard or deleted while the app is closed. The token can be removed with the app's disconnect action or through Keychain Access by searching for the service name above.

## Third party

MarvelSnap.pro receives the data required for account linking, synchronization, and card artwork delivery and applies its own privacy practices. DotGG receives only an anonymous public catalog request and standard network metadata. SnapSync does not send account or game data to DotGG or any other destination.
