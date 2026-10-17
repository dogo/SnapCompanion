# SNAP network investigation — October 16, 2026

Initial pass: the installed artifact, existing local logs, and SnapCompanion's read path. No changes were made to the game, proxy, certificates, or traffic. No new payload capture was acquired.

## Identity and sources

- REA `inspect_plist`: SNAP `com.nvsgames.snap`, version **57.17.0**, build **327**. Evidence: `ev_c593587da9120f53a4a2cf410bbbbd770872de011fe6e7a94b1c33d2de97f463`.
- Framework selected in REA: `/Applications/SNAP.app/Wrapper/SNAP.app/Frameworks/UnityFramework.framework/UnityFramework`, ARM64, SHA-256 `ce77aa7e6311ea4d473edd07efcc7fe82f6456b61107ed58e0d4788d0baf5777`.
- IL2CPP metadata: `Data/Managed/Metadata/global-metadata.dat`, format version 31, SHA-256 `1f5b65b5f276de45a40c584fd5cc20f89f856b0661d282dc946a152d220d850f`. The names below were extracted directly from the string table, outside REA; this does not recover relationships between types and fields or establish execution.
- Game log: `ErrorLog.txt`, under `Data/Documents` in container `93FED5CA-23D5-4F41-BAA2-5DDDEC4011D8`. The read covered 2,313,409 bytes, SHA-256 `6c3a335d450bc744afe1f90a783b8b8ee3664dff981e99108b689225bce53566`. The file was active and may grow; the digest identifies only the bytes read at that time. The raw log was not copied into the repository.
- Source files inspected: `FlowMITM.swift`, `TransparentProxyProvider.swift`, and `MatchTracker.swift`. The queried graph was stale relative to HEAD; implementation findings came from the current files.

## Log observations

Recorded hosts: `global-cf.nvprod.snapgametech.com`, `us-east-1-cf.nvprod.snapgametech.com`, `us-east-1-ws-cf.nvprod.snapgametech.com`, `us-west-2-ws-cf.nvprod.snapgametech.com`, and `shop.shop-prod.snapgametech.com`. Their presence in the log does not prove that all these connections remained open.

Counts of `RemoteGame|OnRequest` and `RemoteGame|ProcessResponse` records in the inspected excerpt, spanning several matches/connections:

| Recorded request | Occurrences | Recorded response | Occurrences |
| --- | ---: | --- | ---: |
| ConnectAccountRequest | 18 | ConnectAccountResponse | 18 |
| JoinRequest | 16 | JoinResponse | 16 |
| GetChangesRequest | 204 | GetChangesResponse | 204 |
| StartTurnRequest | 80 | StartTurnResponse | 80 |
| StageEntityRequest | 131 | StageEntityResponse | 131 |
| EndTurnRequest | 164 | EndTurnResponse | 161 |
| UndoEndTurnRequest | 1 | UndoEndTurnResponse | 1 |
| RaiseStakesRequest | 9 | — | — |
| AckGameResultRequest | 15 | — | — |
| ConcedeImmediatelyRequest | 1 | — | — |

There are also 28 `EditResponse` records. The table does not pair requests and responses by RequestId. Count differences or an unlisted response do not establish packet loss or a server failure.

The logs contain request identifiers, latency, message size, WebSocket state, send/receive counters, and queue depth. They also contain `ChangeCountLatest`, `ChangeCountRequested`, `ChangeCountProcessed`, `Request.Index`, `Request.Count`, `response.Index`, and `response.Changes.Count`.

**Inference:** the client synchronizes changes by position/count, requests batches, and separately tracks what it received and processed. Some `CountMismatch` records show a request for 80 changes and a response with 40; this alone does not demonstrate a defect.

## Client declarations still requiring payload confirmation

Names present in the IL2CPP string table:

| Area | Candidate types |
| --- | --- |
| Energy and priority | `PlayerEnergyChange`, `PlayerInitiativeChange` |
| Card attributes | `CardCostChange`, `CardPowerChange`, `CardStatUpdatesChange`, `CardTextRemovedChange`, `CardOverrideAbilityChange` |
| Identity and movement | `GameCreateCardChange`, `GameRevealCardChange`, `CardMoveChange`, `CardOwnerChange`, `CardMorphChange` |
| Turns and staged actions | `GameStartTurnChange`, `GameEndTurnChange`, `GameUndoEndTurnChange`, `GameWaitingForEndTurnChange`, `GameCreateStagingOptionsChange`, `OpponentStagingStartChange` |
| Locations | `LocationPowerTotalsChange`, `LocationTransformChange`, `LocationShuffleChange`, `LocationStatUpdatesChange` |
| Cubes and results | `PlayerStakesRaisedChange`, `GameStakesRaisedChange`, `GameResultChange`, `GameBattleResultChange` |
| Social interactions | `EmoteNotification`, `ReactionNotification` |

There are also names related to reconnection and requests such as `GetChangesRequest`, `StageEntityRequest`, `EndTurnRequest`, `RaiseStakesRequest`, and `ConcedeRequest`. The artifact contains `*CheatRequest` names; their presence does not establish availability, authorization, or server acceptance. No such requests were sent during this investigation.

This pass found no evidence that the identities of an opponent's hidden cards are sent before their reveal. Entity identifiers and zone counts are not card identities.

## Data SnapCompanion already uses

The proxy selects process `com.nvsgames.snap`, TCP/443, and applies MITM when the SNI matches the host check `-ws-cf.nvprod.snapgametech.com`. Other flows use passthrough. The API pinning rationale is documented in the source comments and documentation; it was not retested.

`FlowMITM` forwards both directions but feeds `WebSocketFrameParser` only with server → game traffic. `TransparentProxyProvider.observe` passes the message to `MatchTracker` and writes `/tmp/snapcompanion-live-match.json` when the snapshot changes. This path does not record complete payloads.

The tracker already interprets players/profiles, revealed and generated cards, movement between zones, hand/deck counts, the known graveyard, locations/power, turns, snaps/cubes, and `GameResultChange`. Older documentation describing results solely as reads from `GameState.json` does not cover this entire implementation.

**Main gap:** additional types exist in the client, but the snapshot discards information the tracker does not model. The overlay file cannot reconstruct the original envelopes or expose every received field.

## Question status and next experiment

- **Channels and request families:** partially answered by historical logs and proxy source.
- **Synchronization mechanism:** partially answered by recorded indices/counters.
- **Fields actually received during each action:** open; requires envelope capture.
- **Reconnection, omitted values, and mode variations:** open; requires capture and timing correlation.
- **Native analysis:** `inspect_macho(detail: summary)` exceeded the 60 s limit. The string search failed while waiting for the Hopper bridge (120 s); the window showed analysis in progress, with no license or loader dialog. That search returned no native strings or functions. Separately extracted metadata must not be presented as REA decompilation output.
- **Preservation and cleanup:** REA evidence was exported to `.build/rea-network-evidence-2026-10-16.json` (one record, identity from the plist). `close_binary` returned `cleanup_incomplete`, without authenticated shutdown confirmation, retaining `/tmp/rea-L10TsX`. A later UI check showed only an empty `Untitled` document, without the framework open. The temporary directory was not deleted.

The initial pass identified the need for a temporary, bounded local capture of decoded messages, including direction, time, type, and keys/fields while excluding credentials and personal identifiers. The next step was to correlate playing/moving cards, ending/undoing turns, snapping, and results with their envelopes. Overlay summaries alone cannot close the payload gap.

## Structural capture implemented

The diagnostic build can be launched with `--capture-network`. It activates the existing proxy and configures a 15-minute window. The deadline is stored in `providerConfiguration`; restarts after that deadline do not reactivate capture. A normal launch does not request capture.

The `messages.jsonl` file is created in a `snapcompanion-network-<UUID>` directory under the extension's temporary directory. Its path is recorded in the `br.com.anykey.SnapSync.proxy` log. Directory permissions are 0700 and file permissions are 0600; reading may require administrative access because the extension runs as root.

Each line includes a Unix timestamp, direction, random connection identifier, original size, and the message's JSON structure. Scalar values are replaced with `<string>`, `<number>`, and `<boolean>`, preserving null and message type names. Dynamic keys outside the field-name format are replaced. JSON embedded in text is also sanitized. This capture therefore discovers families and fields, **not complete values or correlations between original RequestIds**.

Limits: 8 MiB of admitted messages, 8 MiB of output, and 2 MiB per message. Non-JSON frames are not recorded. Writes and sanitization run on a queue separate from forwarding. The WebSocket parser was moved into the core to test masked client requests and server fragments with interleaved pings. The complete suite passed with 51 tests; in-match verification remained pending.

### Local installation confirmed

A universal Release build was compiled and validated. Version 43 was installed in `/Applications/SnapCompanion.app` and launched with `--capture-network`. At 23:28:26 local time, the provider process logged `MITM server context loaded=true` and `startProxy applied, error=nil`, plus creation of `messages.jsonl` under `/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T/snapcompanion-network-AD17B316-02A0-4BE1-8A69-CEBB154FB1D7`. This session's deadline was approximately 23:43.

The previous installation's signing combination was reproduced: Developer ID Application for the app and Apple Development for the extension, with a development profile and the `app-proxy-provider` entitlement. The project's distribution files retain `app-proxy-provider-systemextension`; this local package used a generated `.build/network-capture-development.entitlements` and the previous extension's profile. Requesting the distribution entitlement with the development profile let version 42 register as active but prevented its process from starting. This was confirmed in `taskgated-helper` logs and corrected in version 43.

Before that distinction was identified, the initial Developer ID package was submitted to Apple for notarization and later accepted (ID `fe14a9e3-3efe-47c8-b5ca-13a5d878bb5e`). No logs or captures were uploaded. The user instructed us to continue with local tests and no further uploads; version 43 was signed again locally and was not submitted. The previous copy was preserved in `.build/SnapCompanion-before-network-capture.app`.

## Captured match results — 23:28:57 to 23:32:36

The user played a match and copied the private file using administrative authentication. The analyzed copy is `.build/network-capture-match.jsonl`: **109 records**, 430,238 bytes, SHA-256 `c25b57ec764d32ea8e4f81ce967f1cc1f304417926eaf07d0ba6503b374bef3b`. It contains 50 client → server messages, 59 server → client messages, and two connection identifiers. The summary and field inventory are in `.build/network-capture-summary.json`. Both remain outside Git. Copy validation confirmed that structural scalar values are type markers or permitted message names.

This runtime evidence was analyzed as SnapCompanion's custom JSONL using Python; **it was not imported as HAR or analyzed by REA's capture parser**, which does not advertise support for this format. REA artifact identification remains in the initial section. The line numbers below identify records in the copy with the digest above.

### Observed flow

1. **Matchmaking over WebSocket:** `CubeMatchmaker.ConnectAccountRequest/Response`, `FindMatchRequest`, `MatchResponse`, and `MatchFoundNotification` (lines 1–5). The notification includes `GameHostUrl`, `GameId`, league, and two players with profile/clan data. Interception therefore covers matchmaking as well as match changes.
2. **Game connection:** `CubeGame.ConnectAccountRequest/Response`, `JoinRequest/Response`, and the initial changes query. The connection response includes `ChangeCount`, `CurrentState`, `SerializationType`, and exception filters; these fields' scalar contents were masked.
3. **Synchronization:** 17 `GetChangesRequest/Response` pairs; requests contain `Index` and `Count`, responses contain `Index` and `Changes`. Eight `ChangeNotification` messages carry `AccountId`, `Count`, and `GameId`, without a `Changes` array in this sample. This supports distinguishing availability notifications from batch retrieval.
4. **Plays:** six `StartTurnRequest/Response` pairs, 12 `StageEntityRequest/Response` pairs, and ten `EndTurnRequest/Response` pairs. `StageEntityResponse` delivers changes immediately, plus `Accepted` and `TimeRemainingMilliseconds`. `EndTurnRequest` includes `StageEntityRequests`; its response includes `StageEntityResponses` and `CanUndoEndTurn`.
5. **Completion:** `GameResultChange` on line 107, `AckGameResultRequest` on 108, and `EditResponse` on 109. The result contains a structured `Message` object after JSON sanitization, including per-account results and match metrics.

Staging messages also embed `PreviousRequests` and `PreviousStageEntityResponses`. A recursive search finds 36 `StageEntityRequest` occurrences, but only 12 are transmitted envelopes: **do not count embedded objects as new transmissions**. The change counts below are occurrences directly in server envelopes' `Changes`, not unique entities or events deduplicated across responses.

### Additional data confirmed in transit

| Information | Observed type and fields | Direct occurrences |
| --- | --- | ---: |
| Energy | `PlayerEnergyChange`: `EntityId`, `CurrentEnergy`, `DefaultEnergy`, `StatUpdates` | 37 |
| Initiative | `PlayerInitiativeChange`: `PlayerEntityId` | 7 |
| Updated cost | `CardCostChange`: `EntityId`, `Cost` | 13 |
| Updated power | `CardPowerChange`: `EntityId`, `Power` | 28 |
| Staging options | `GameCreateStagingOptionsChange`: `PlayerEntityId`, `Options` with entities, targets, blocking reasons, and undo data | 19 |
| Card modification history | `CardStatUpdatesChange`: `EntityId`, `StatUpdates` | 40 |
| Location modifications | `LocationStatUpdatesChange`: `EntityId`, `StatUpdates` | 72 |
| Detailed reveal | `GameRevealCardChange`: identity, cost/power, overridden ability, references, and `StartedInDeckEntityId` | 27 |

Options include `TargetEntityIds`, `NoStageOptionReason`, `UndoTargetEntityId`, and sometimes `UndoTargetZonePosition`. This confirms that the channel carries interaction options as well as visual events. The reason values and which player owns each entity cannot be reconstructed from this sanitized capture.

There were also 373 `VfxChange` occurrences with structured context, 52 `LocationPowerTotalsChange` occurrences, and changes for movement, reveal, resolution, card resets, location transformations, and cubes. VFX interpretation is not required to obtain energy/initiative/cost/power: dedicated changes exist for these values.

### Tracker gaps identified through runtime evidence

- **Initial card-origin hypothesis, later not confirmed:** all 27 reveals in this first capture contain `StartedInDeckEntityId` without `CreatedBy*`. This raised a concern about the generated-card filter. The second match demonstrated that `CreatedByCardDefId` is sent for generated cards and omitted for originals; the current rule passed the real case. See the final validation below. Its absence on normal cards is not a protocol incompatibility.
- **Energy, initiative, cost, power, and options:** the current tracker does not model the dedicated families above. The capture confirms their availability in this match but does not calibrate values or ownership/zone changes for a new implementation.
- **Optional fields:** `CurrentEnergy` appears in 31 of 37 energy changes; `Power` appears in 23 of 27 reveals; `LocationSlot` appears in two of three location creations. This establishes field omission, but the sanitized copy alone cannot show that every absence means zero. A new reader must respect each type's semantics.

### Data received in the final result

`Message` contains `FinalCubeValue`, `TotalTurns`, `TurnsTaken`, `AllTurnsPlayed`, `LocationDefIdsAtEndOfGame`, and `GameResultAccountItems`.

This match had **a single account entry**. It contains `IsWinner`, `EnergySpent`, `CardsDestroyed`, `LocationResults`, `LocationWinRecord`, rewards, `CardDefIdsDrawn` (11 items), `CardDefIdsPlayed` (10 items), `CardsSeen` (27 tuples), and a `Deck` with 12 entries in `Cards` and `CardIds`. List lengths do not establish unique cards. The exact meaning of the `CardsSeen` tuples remains unresolved.

`AccountId` values were masked, so this copy cannot attribute the entry to the local player or opponent. **There is no evidence here of the opponent's complete deck being sent or of hidden card identities arriving before reveal.** The 35 direct `GameCreateCardChange` occurrences carry owner/zone/card-back data without `CardDefId`; identity appears in `GameRevealCardChange`.

### Limits and evidence-based next step

This pass confirms the structure received in one match, covering matchmaking, six turns, and the result. It does not validate other modes, disconnection/reconnection, actual clock/energy values, or account/entity attribution. The tracker was not modified based solely on these names.

The next useful experiment should preserve only an explicit list of game values needed for calibration—for example, entities, `StartedInDeckEntityId`, turn, energy, and initiative—while keeping credentials, names, and account identifiers masked. This would allow checking card origins and player mappings before adding those values to the overlay. Repeating a generic capture that suppresses every number is not needed to answer these questions.

## Additional validation through local state and calibration capture

A read of `GameState.json` persisted after this match was preserved in `.build/network-match-state-private.json`, with permissions 0600 and outside Git. SHA-256: `c76618aa202eda7f15a091a85e727d4833996653aa363e02117a56c267d59129`, 178,411 bytes; the source file was updated at 23:32:50. JSON.NET `$id`/`$ref` references were resolved using an in-memory index. A summary without names or real account identifiers is in `.build/network-match-state-summary.json`.

### Facts resolved in the snapshot

- `ClientGameInfo` identifies the local player as entity 2 and the opponent as entity 7. Their decks are entities 3 and 8, respectively; the opponent's hand is entity 9.
- The only entry in `ClientResultMessage.GameResultAccountItems` has the same `AccountId` as `ClientPlayerInfo`. Therefore, **the complete deck stored in this local result belongs to the local player**, resolving the initial diagnostic ambiguity. The preceding network capture preserved only the structure of this same format, without the IDs needed for that comparison.
- Known opponent cards in the entity registry have `StartedInDeckEntityId = 8`; known local cards have 3. This is a positive control for interpreting the field on cards that started in those decks.
- Three cards remained in the opponent's deck and one in their hand. None of these four objects has `CardDefId`. Unknown objects in the set-aside zone must not be counted as deck or hand cards; the snapshot contains 11 entities in that zone.
- Opponent profile: `CollectionScore = 13879`, `HighWatermarkRank = 99`, `CollectionPrivacy = Private`. `ProgressionData` contains `SnapPoints = 4377` and `NumGamesToCompleteOnBoarding = 60`. This does not demonstrate MMR, the actual number of games played, or current rank. Do not infer those concepts solely from field names.

### Status of the suspected bug

The first capture showed only that known cards lacked `CreatedBy*`; **this did not demonstrate a bug**. Identifiable cards in that snapshot point to their original decks. The generated-card control in the second match confirmed that the current rule works, as described in the final validation section. No rule based on an assumed sentinel was introduced.

### Calibration capture installed — version 44

Format 2 retains the `shape` envelope but preserves only explicitly permitted field values: entities/zones/original decks, turn, energy, initiative, cost/power, clock, indices, numeric request identifiers, selected profile data, and card/location definitions. Real account IDs are replaced with stable `account-N` aliases within the session, allowing notifications, players, and results to be linked. Unknown text, names, and other identifiers remain masked. Credential subtrees are removed.

The capture directory is now created exclusively under `/private/tmp`, with permissions 0700, and its file has permissions 0600. Both belong to the user who launched the app; ownership changes apply only to the newly created diagnostic output. This allows analysis without copying data from a root temporary directory through `sudo`. Existing directories are not reused. Tests verify permitted-value retention, secret removal, alias stability, and refusal to overwrite.

The complete suite passed with **53 tests**. The universal Release build and local signatures were validated; there was no further submission to Apple. At 23:42:21, extension 44 confirmed creation of `/private/tmp/snapcompanion-network-706051FC-F8C2-4507-A22C-52DE24A054C6/messages.jsonl`, a loaded MITM context, and `startProxy applied, error=nil`. Ownership and permissions were checked as the normal user. The capture window ended around 23:57.

Pending experiment: play a card that generates another card, such as Agent 13, then play the generated card. Compare their reveals with normal cards and `DeckEntityId`, then reproduce the case in a test before fixing the tracker. The same capture can verify energy/initiative attribution and which additional profile or card data the server actually sends; it does not assume access to information the server does not transmit.

## Final validation — second match, 23:44:48 to 23:49:06

Local format 2 capture: `.build/network-capture-calibration.jsonl`, 603,576 bytes, **120 messages** (55 client → server, 65 server → client), SHA-256 `eb695d7fa28ffd018c42a59fa9980bb4af12f5c0a7bac78d83725f0b39b50ed4`. The record numbers below refer to this copy. The summary is in `.build/network-calibration-summary.json`; none of these files was sent to third parties.

### The suspected bug was not confirmed by this control

`ChangeNotification` identifies `account-2` as the local account. `GameCreatePlayerChange` maps it to entity 7/deck 8 and the opponent `account-1` to entity 2/deck 3.

| Observed case | Entity | Transmitted origin | Record |
| --- | ---: | --- | ---: |
| Opponent's original Mr. Negative | 25 | `StartedInDeckEntityId: 3`, no `CreatedBy*` | 46 |
| Opponent's original White Tiger | 20 | `StartedInDeckEntityId: 3`, no `CreatedBy*` | 118 |
| Opponent's two Tiger Spirits | 57 and 58 | `CreatedByCardDefId: WhiteTiger`, no `StartedInDeckEntityId` | 118 |
| Card generated by the local Agent 13: Infinity Ultron | 56 | `CreatedByCardDefId: Agent13`, no `StartedInDeckEntityId` | 116 |
| Local Dagger generated by Maria Hill | 46 | `CreatedByCardDefId: MariaHill`, no `StartedInDeckEntityId` | 35 |
| Local Moon Girl copies | 51, 52, and 53 | `CreatedByCardDefId: MoonGirl`, no `StartedInDeckEntityId` | 99 |

`CreatedByPlayerEntityId` also appears on generated cards, although its value was not allowlisted and was replaced with a marker. No numeric origin sentinel was observed for these cards: `StartedInDeckEntityId` was **omitted**, not sent as -1.

The snapshot written by the app at match end was compared with the capture: `opponentDeckCards` contains the seven revealed original names (Magik, Iron Man, White Tiger, Scarlet Witch Queen of Chaos, Wong, Mr. Negative, and Ravonna Renslayer), excluding Tiger Spirit and the three generated spells. `opponentCards` includes these known effects, as expected. The two Tiger Spirit entities do not become two entries with the same name.

A test was added using a minimal projection of actual records 12, 13, 15, 46, and 118: `Tests/SnapSyncCoreTests/Fixtures/Network/GeneratedCardsCalibration.json`. The `excludesWhiteTigerTokensFromCapturedMatchDeck` test passed with the existing logic, as did the complete suite with **54 tests**. Only the field-origin comment was updated; **no tracker behavior change was needed**. This validates the observed cases, not every theft, transformation, or ownership-transfer mechanic.

### Additional opponent data confirmed

Outside `PlayerInfo`, `MatchFoundNotification` contains `Rank: 89` and `SnapPoints: 4775` for `account-1`. `PlayerInfo` reports `HighWatermarkRank: 106` and `CollectionScore: 21614`. The channel therefore contains both the match rank field and the highest rank reached, while the current tracker only uses the latter.

`GameCreateChange.Players` also contains `InfiniteLeaderboardSkillRating`. Its value was masked by the capture allowlist; the field's presence and name do not establish its operational meaning or justify calling it MMR. No explicit bot indicator was found in this sample or in the limited saved-state search for `IsAi`, `IsBot`, `AiConfigDefId`, and `AiPlayDefId`; this does not prove that the opponent was human.

Energy and initiative were attributed to known entities: the server sent both players' default/current energy and initiative changes. The match lasted seven turns and ended with eight cubes. Missing energy values coincided with spending all energy, supporting the need to handle type defaults when implementing a reader.

### Limits of hidden information

In the final snapshot of this second match, the opponent retains three cards in hand and two in the deck, all without `CardDefId`. An ordered search of direct changes found no `CardCostChange`, `CardPowerChange`, `CardStatUpdatesChange`, or `CardReferenceCardsChange` for opponent cards before their first reveal. This search is limited to those types, this capture, and data received by this client; it is not proof about every game path.

Mirage's ability gave the local player a copy of Iron Man in record 59, marked `CreatedByCardDefId: Mirage`; the opponent's original card was only revealed as entity 17 in record 101. The copy did not include a reference to the original entity (`ReferenceCards` was empty). Information can therefore arrive through a game effect before the opponent card's direct reveal, but without a sufficient entity link to identify the rest of the hand or deck arbitrarily.

Another match is not needed to confirm the generation rule in these cases. Investigating the still-masked rating value or other mechanics requires a specific question and capture; repeating the same generic test is not justified.

## Next requested control: ownership, transformation, and rating — version 45

The user requested progress on these three points. Capture now also preserves `CreatedByPlayerEntityId`, `OverrideAbilityFromPlayerEntityId`, `CardZonePosition`, `InfiniteLeaderboardSkillRating`, and `InfiniteLeaderboardStanding`. The new test only verifies that these fields survive sanitization and credentials remain removed; it is not a protocol-conformance test or a test of the tracker's `CardOwnerChange`/`CardMorphChange` handling. Its values are synthetic.

At this stage, the tracker has no explicit branches for `CardOwnerChange` or `CardMorphChange`. This is an investigation point, not a confirmed bug: runtime evidence must show whether the server also sends creation/reveal changes that already update state. Transfers require distinguishing the current owner from the original deck; receiving a card from the opponent does not prove that its type started in the recipient's deck. Transformations require following the same entity before/after and separating its current and original identities.

The IL2CPP string list contains both types. It also contains `InfiniteLeaderboardSkillRating` and rating-update names, but static names do not demonstrate use in matchmaking. Official support describes MMR as hidden and Snap Points as derived from MMR and seasonal performance: [How do Ranks work?](https://marvelsnap.helpshift.com/hc/en/3-marvel-snap/faq/30-how-do-ranks-work/?p=all). None of the observed fields was therefore automatically labeled as internal MMR.

Before the new match, local `ProfileState.json` contains `ServerState.LeaderboardLog.InfiniteLeaderboardSkillRating = 4590` and `InfiniteLeaderboardDetails.SkillRating = 4590`. The reference and read digest were saved in `.build/network-rating-baseline.json`, without account IDs and with permissions 0600. This log may represent leaderboard state from another point in the season; its updates and equivalence to the transmitted value still require comparison.

Requested experiment: play Green Goblin to switch sides and Morph to change identity. Their local catalog descriptions confirm these basic functions. Record whether the effects actually occurred; blocked effects or cards that were never drawn are not positive controls. The hidden-identity search remains limited to received messages and the local snapshot, preserving account IDs as aliases.

The universal Release build and local signatures were validated; **55 tests passed**, with no further upload to Apple. Extension 45 activated at 23:56:16 with `startProxy applied, error=nil`, writing `/private/tmp/snapcompanion-network-291A8D1D-2878-4485-88D9-88BA52CF155D/messages.jsonl`. The file is private and readable by user `dogo`. Capture was valid until approximately 00:11 on October 17, 2026. Conclusions from these controls awaited the match.

## Third match: Morph observed, ownership transfer still pending

The user reported that only Morph was drawn. The capture contains **127 messages**, 871,346 bytes, between 23:58:39 and 00:02:07 (October 16–17), with 59 client → server and 68 server → client messages. Private copy: `.build/network-ownership-capture.jsonl`, SHA-256 `db6892847ec2ace553617cd10c6ba89fa344682c21591ca3947d2df2377df6c7`. It contains one `CardMorphChange`, zero `CardOwnerChange`, and 31 direct `GameRevealCardChange` occurrences.

### Transformation bug reproduced and fixed

- Record 14: Morph is revealed to the local player as entity 37, owner 7, original deck 8.
- Record 41: `CardMorphChange` changes **the same entity 37 to Venus**, with `CreatedByCardDefId: Morph` and `StartedInDeckEntityId: 8`. A later `CardReferenceCardsChange` in the same batch references Morph. Sinister London creates a separate Venus copy, entity 48, correctly marked `CreatedByLocationDefId: SinisterLondon`.
- Record 86, approximately 69.8 seconds later: another reveal of entity 37 carries Venus with `CreatedByCardDefId: Morph`, this time without the original-deck field.

The previous tracker ignored `CardMorphChange`. The later reveal also caused the generated-card filter to exclude the original entity from prediction, losing the fact that the starting card was Morph. These are separate issues from the initial false alarm about generated cards.

The minimal fixture `Tests/SnapSyncCoreTests/Fixtures/Network/MorphCalibration.json` derives from records 11, 12, 14, 41, and 86. **Morph belonged to the local player in the capture**; the test explicitly swaps the reference account to exercise opponent tracking with the same sequence. This does not claim that the overlay displayed an opponent Morph in this match. Before the fix, the test reproduced two failures: known cards `[Morph, Venus]` after transformation, and no original deck card after the later reveal. The expected current identity is Venus and the original deck identity is Morph.

The shared-code fix:

- Processes `CardMorphChange` alongside reveals to update the current identity immediately.
- Stores the first known identity of original cards separately, preserving it in deck prediction after transformation.
- Keeps persistent tracking of generated entities, excluding the Sinister London copy and other tokens.
- Clears this original-card registry when another match starts.

The captured-case test passed after the change, and the complete suite passed with **56 tests**. Previous Maria Hill/White Tiger and generated-copy validations still pass. The snapshot API did not change. Ownership transfers still lacked a runtime control and were not implemented using assumed fields.

### Rating: values obtained, internal MMR still not established

| Account in this session | `MatchFoundNotification.Rank` | `SnapPoints` | `GameCreateChange.Players.InfiniteLeaderboardSkillRating` |
| --- | ---: | ---: | ---: |
| Opponent (`account-1`) | 91 | 4464 | 4464 |
| Local player (`account-2`) | 85 | 4777 | 4777 |

The opponent profile also reports collection level 19,172 and highest rank 93. The local value saved in `LeaderboardLog.InfiniteLeaderboardSkillRating` remained **4590** after the match, distinct from the transmitted 4777. The two network fields therefore match in this sample, but this does not prove that they expose current internal MMR. Local state may have a different temporal/seasonal scope. No explicitly named MMR fields were observed in this bounded analysis.

### Hidden cards and limits of this match

The final snapshot preserved in `.build/network-morph-state-private.json` was resolved through `$id`/`$ref`. The opponent's two remaining hand cards and three deck cards still lack `CardDefId`. The summary and digests are in `.build/network-morph-summary.json`. Entity 37 ended with definition Venus and creator Morph, without an origin field in final state, supporting the need to retain the already-known original identity.

Morph exposed Venus through its intended effect before the opponent's original Venus was directly revealed (record 50). This does not reveal other cards arbitrarily or provide the complete deck. A positive ownership-transfer control still requires a match where Green Goblin, Hobgoblin, or another effect actually switches a card's side.

The fix was compiled, signed, and installed locally in extension **46**, without another upload. At 00:06:41, the provider confirmed `startProxy applied, error=nil`; `systemextensionsctl` confirmed version 46 active. The new private capture, readable by the user, is `/private/tmp/snapcompanion-network-E63B7C1E-128F-4623-A02A-2D2ECD9FDD5C/messages.jsonl`, valid until approximately 00:21. The next requested control is only an actual side switch using Green Goblin or Hobgoblin; Morph already supplied the case needed for the fixed bug.

## Fourth match: Hobgoblin and Green Goblin confirm ownership transfer

The user confirmed that both goblins switched sides. The capture contains **97 messages** (44 client → server and 53 server → client), 376,867 bytes, between 00:08:50 and 00:11:48 on October 17, 2026. Private copy: `.build/network-owner-transfer.jsonl`, SHA-256 `1604a66e743465674119624f1605f78fa710b0f7a127bca2722efe592d03e0db`.

In this session, local player = `account-2`, entity 7, deck 8; opponent = `account-1`, entity 2, deck 3.

| Record | Event | Entity | Current owner | Original deck |
| --- | --- | ---: | ---: | ---: |
| 14 | Green Goblin creation and reveal | 29 | 7 | 8 |
| 46 | Hobgoblin reveal | 33 | 7 | 8 |
| 55 | Hobgoblin `CardOwnerChange` | 33 | 2 | retained: 8 |
| 70 | Green Goblin `CardOwnerChange` | 29 | 2 | retained: 8 |

The received format uses **`CardEntityId` and `CardOwnerEntityId`** in `CardOwnerChange`, alongside `LocationEntityId: 13`. Green Goblin also includes `CardZonePosition: 2`. Before each transfer, the same batch contains a `CardMoveChange` still reporting owner 7; the later update to owner 2 must take precedence. No new creation implicitly updates ownership.

Final game state confirms both entities with `Owner.EntityId: 2` and `StartedInDeckEntityId: 8`. Private copy `.build/network-owner-state-private.json`, SHA-256 `499500b6607a19174278d7b6cb32fa5b5db44c5bbd1fb43128c371666375a97d`.

### Bug reproduced and fixed

The tracker ignored `CardOwnerChange`: transferred cards remained associated with their initial owner. The minimal fixture `Tests/SnapSyncCoreTests/Fixtures/Network/OwnerTransferCalibration.json` retains the required events from records 11, 12, 14, 46, 55, and 70. The test runs with the actual reference account and with the perspective explicitly reversed. **The real capture contains local goblins sent to the opponent**; the reversed perspective is a test replay, not a second observed match.

Before the fix, the test failed four current-owner checks. Shared code now processes ownership events and the owner reported in movements, respecting received order. A separate map retains the original deck owner; when available, `StartedInDeckEntityId` identifies the original deck directly, including when the card had already been transferred at first observation. As a result:

- Both goblins enter the opponent's known cards, but **not** their original deck cards.
- In the reversed test perspective, the goblins leave the opponent's controlled cards while still identifying their original deck.
- Tests for Morph's original identity and generated-entity exclusion continue passing.

The complete suite passed with **58 tests**, including an additional synthetic case for first observation after transfer. The snapshot API remained unchanged. The fix is included in extension 47; local activation is recorded below after build and signature validation.

### Additional information and limits

Opponent values were `Rank: 85`, `SnapPoints: 4358`, and `InfiniteLeaderboardSkillRating: 4358`; the local player retained 4777 in both network fields. This repeats the observed equality between Snap Points and the rating field, without establishing access to internal MMR.

In final state resolved through `$id`/`$ref`, **all eight opponent deck cards still lack `CardDefId`**. The hand contains three entities: two unidentified and one identified as Hope Summers. This match therefore also does not demonstrate access to the complete hidden deck. Entity, zone, and owner IDs are observable even when card identity is not transmitted.

Positive controls for transformation (Morph) and transfer (both goblins) are complete. Another match is not needed for these bugs. Local installation does not involve another notarization submission.

The universal Release build completed, signatures were verified with `codesign --verify --deep --strict`, and version 47 was installed in `/Applications/SnapCompanion.app`. `systemextensionsctl` confirmed **47 activated enabled**. At 00:15:46, the provider logged `MITM server context loaded=true` and `startProxy applied, error=nil`. Activation used the existing live-tracking shortcut, **without `--capture-network`**, ending the previous capture session and resuming normal tracking. There was no further upload to Apple. The fix was validated by replaying captured messages and running the suite; no further match was played after installation.

## Focused investigation: access to the complete hidden deck — October 17, 2026

The user requested that this stage focus on whether still-hidden identities are available to the client. Separate questions: (1) explicit identities and early references in captures; (2) duplicates/references/results in saved state; (3) the client's declared visibility mechanism; (4) effect fields masked by the previous capture. Limited results for the first three follow; the fourth awaited capture 48. Complete deck access was not demonstrated.

### Captures: identities and event order

The local analyzer `.build/analyze_hidden_cards.py` (ignored by Git) audits the three captures that retain values and states its limits explicitly, including ownership attribution, zones, cosmetics, and card effects. It includes a synthetic self-check. Output: `.build/hidden-capture-analysis.json`.

The three v2 captures total **344 records**, 158 client → server and 186 server → client. There are **152 `CardDefId` occurrences**: 86 in changes, 21 in card references, nine in avatars, and 36 in the three local decks returned after matches. Avatars are not evidence of deck composition. The initial 109-record capture preserved only the schema and cannot attribute cards.

Of 33 first identities of entities created for the opponent, 32 arrived outside deck/hand zones. One arrived while still in the deck: **Hope Summers, entity 49, record 70/change 51 of the goblins match**. This card had `CreatedByCardDefId: Loki` and was revealed while processing Iron Lad's effect (entity 17), which copied its ability. Entity 49 later moved to the hand. This identifies one specific card still hidden in its zone through a specific mechanic; it does not reveal the entire initial deck. No `ReferenceCards` explicitly linked to an opponent entity appeared before that entity's first reveal in this search.

### States: resolving references does not recover absent identities

The `.build/analyze-hidden-states.py` script resolved **3,337 JSON.NET objects and 732 references**, with no missing references, across the three saved states. Private report: `.build/hidden-state-analysis.json`.

| State | Known identities in remaining opponent deck | Known identities in remaining opponent hand |
| --- | ---: | ---: |
| First state capture | 0/3 | 0/1 |
| Morph | 0/3 | 0/2 |
| Goblins | 0/8 | 1/3 |

The **19 still-unknown entities** have no definition, ability, modifiers, components, cost, power, or references identifying the card. No other instance of the same `EntityId` has an alternative definition. The known Hope Summers in hand is the entity from the Iron Lad case above.

`ClientResultMessage.GameResultAccountItems` contains only the local account and its 12 cards in all three states. Counting must use `Deck.Cards`: a broad scan of `Deck` also included the Black Bolt avatar card, producing a false total of 13 in the first state.

Abilities provide partial composition inference: Cyclops, Misty Knight, and Abomination reference High Evolutionary without a corresponding `EntityId`. This suggests an archetype card but does not identify any still-hidden slot. Morph/Venus/Hulkbuster references also explain already-observed effects without supplying the rest of the deck.

### IL2CPP client: structured visibility declarations

This stage went beyond searching isolated strings. The `.build/inspect_snap_metadata.py` parser read v31 tables, validating bounds, alignment, strings, ranges, and method owners. Artifacts: `.build/hidden-metadata-analysis.json` (836 related types) and `.build/hidden-metadata-focused.json` (12 central types). The metadata digest remains `1f5b65b5f276de45a40c584fd5cc20f89f856b0661d282dc946a152d220d850f`.

Layout reference: [Il2CppDumper/MetadataClass.cs](https://raw.githubusercontent.com/Perfare/Il2CppDumper/master/Il2CppDumper/Il2Cpp/MetadataClass.cs), local copy SHA-256 `d66c9f867e66bf7709a2789b708c846517241e6aa54e8a6480271720b5fcc3cd`.

- `CubeGame.GameCreateCardChange`: six fields—EntityId, OwnerEntityId, ZoneEntityId, ZonePosition, CardBackDefId, and CardBackRank. **It does not declare CardDefId.**
- `CubeGame.GameRevealCardChange`: 42 fields, including CardDefId, StartedInDeckEntityId, and ReferenceCards.
- `CubeGame.Card`: `_visibleToPlayerEntityIds`, `IsVisibleTo(player)`, `GetVisibility`, `AddChangeIfVisible`, `RevealTo(player)`, `RevealToAllPlayers`, and `ResetCardVisibility`.
- `CardVisibility`: None, Owner, and All.
- `CubeGame.Game`: `GetChangesForPlayer(accountId[, changes])`, `AddChange(accountId, change)`, `UpdateChangeOwner`, and `ResetAllCardsVisibility`.
- `VfxKey`: declares CardDefId, CardDefIdsList1, CardDefIdsList2, SourceCard, TargetCard, TargetZone, and other context identifiers. This structure is relevant to the new capture; enum presence does not prove transmission of hidden data.

These are **declarations, without method bodies or process-memory data**. They support the existence of a visibility model per player but do not alone prove that every transmission is correctly filtered.

Development commands such as `GetDeckCheatRequest/Response` and a handler are also declared, with PlayerEntityId/CardDefIds. Their presence in the client does not demonstrate production acceptance, authorization, or returned data. No such request was sent.

REA reported Hopper as available, but `open_binary` was blocked by `cleanup_incomplete` from an old session (`/tmp/rea-L10TsX`, hopper-document). The UI displayed an activation window; the available Demo mode was opened without a purchase/license. The shutdown attempt still returned the same blocker; the old PID no longer existed when checked. The bundle exported in this session contains zero records, and no new native decompilation or behavior is attributed to REA. The metadata parser and capture scripts are separate local analyses, not REA decompilation Evidence.

### Specific gap and capture 48

V2 sanitization masked values in `VfxChange.Type/DefType/EntityId` (when a string), `VfxChangeItem.Key`, `VfxString.String`, `VfxListStrings.Strings`, `VfxNumber.Number`, `CardDefIdUpdator`, and `CardStatUpdate.Value`. The preceding captures therefore could not exclude identity encoded in the visual context of a still-hidden card.

Extension **48**, capture format **3**, preserves these effect fields according to their declared type. Generic names String/Key/Type/Number/Value remain masked outside those types. Only identifiers up to 128 characters in the permitted alphabet are preserved. Numeric JSON.NET `$id/$ref` references are also preserved. Credentials remain removed, and AccountId/SenderAccountId remain aliased. Fields not included, such as `CardsSeen.Item1/Item2`, remain an explicit limitation. Unrestricted raw-data recording was not enabled.

**59 tests passed**, including a new test for type-specific retention and protection of the same names in generic objects and credentials. The Release build and local signatures were validated; there was no further upload to Apple. At **00:21:50**, `systemextensionsctl` confirmed version 48 active; the provider logged `MITM server context loaded=true` and `startProxy applied, error=nil`.

Private capture: `/private/tmp/snapcompanion-network-E9B54DA6-346F-4C23-975C-76D7CE35E7DD/messages.jsonl`, limited to 15 minutes / 8 MiB, until approximately **00:36:49**. The user was told that a new normal match, preferably completed, was needed. The control compares visual context for still-hidden draws/plays with later reveals, calibrating against local cards first. Its result was pending at this point; complete access was not promised.

## Fifth match: visual-effect capture results — 00:22 to 00:28

Capture `.build/network-hidden-vfx-capture.jsonl`: **162 records**, 559,540 bytes, 76 client → server and 86 server → client, format 3, between 00:22:16 and 00:28:05 on October 17, 2026. SHA-256 `7b6e0fd5ea535495433b3b516488a3dda659928175433cbdefddbdda80d7a7f4`. Private final state `.build/network-hidden-vfx-state-private.json`, SHA-256 `45408e94ebb8cc73f225d940959453921ff575a1dc95e1a279470fd9e295ed07`.

**The reference account changed in this capture:** local `account-1`, entity 2, deck 3, hand 4; opponent `account-2`, entity 7, deck 8, hand 9. Aliases must not be carried across sessions.

### VFX fields examined: no complete access demonstrated

The analysis covered **381 `VfxChange` occurrences**, including 21 `DrawCard` occurrences. Preserved strings include 160 sets of AbilityDefId/AbilityDefType/AbilityOwnerDefId/AbilityOwnerDefType, five LocationDefId values, and three CardDefId values. There were no `CardDefIdsList1` or `CardDefIdsList2` fields in this match. Entity lists in `VisualTargetCards` are not lists of card identities.

All three VFX CardDefId values are **Spell07NicoMinoru**, record 63/changes 50, 57, and 65. They appear after Nico Minoru, entity 37, was revealed in the same batch (change 45), refer to the card's effect, and do not expose an additional deck card. No explicit opponent card reference preceded its first identity in the main analyzer. Ability declarations require a separate audit of AbilityOwnerEntityId because automatically ignoring them would also be incorrect; the deep report records this control.

Frigga, entity 30, was received while still assigned to the deck in record 63/change 24, immediately before moving to location 14 in change 25 through **Gladiator**. Simply treating “identity while in deck” as a leak would therefore be a false positive. The Joaquin Torres copy, entity 49, received its identity in hand through Frigga in the same batch (changes 33–35); this is also a specific effect.

By match end, all 12 original opponent deck entities (28–39) had been revealed. The last one, Moon Girl, only received an identity in record 160/change 22 during final resolution. Reconstructing those 12 names after their reveals **does not obtain the hidden deck in advance**. The structured result still contains only the local 12-card deck.

### Inferable hidden information: two generated hand cards

The final two hidden slots have a concrete origin link:

| Record/change (zero-based index within the batch) | Observation |
| --- | --- |
| 133/52 | VampireKillmongerEndOfTurnTrigger TriggerStart, ability owner entity 39, visual target 50 |
| 133/53 | Entity 50 created for opponent 7, in hand 9, without CardDefId |
| 133/54 | SpawnCardInHand for 50, SourceCard 39, without explicit identity |
| 160/29 | Entity 51 created for opponent 7, hand 9, without CardDefId |
| 160/30 | SpawnCardInHand by Moon Girl 29, TargetCard 51 and **OriginatingCard 50** |

The official [New Season: Vampires vs. Zombies](https://marvelsnap.com/new-season-vampires-vs-zombies/) announcement describes Vampire Killmonger's ability: at the end of a turn, if all energy was spent, receive a **Vampiric Spear**. The consulted [official October 15 update](https://marvelsnap.com/balance-update-october-15-2026/) does not change that ability. The companion's local catalog does not yet contain this new card, so it was not used to confirm its rule.

**Inference, not a received field:** entity 50 is a Vampiric Spear based on creation attributed to the effect with a fixed outcome; entity 51 is another Vampiric Spear based on Moon Girl's observed copy of 50. The link is present in traffic; the name is inferred from the external rule. This does not establish current power/cost/modifiers, is not a recovered raw identity, and does not supply the entire initial deck. No assumed name or new automatic-inference rule was added to the tracker.

Final state was analyzed in `.build/hidden-vfx-state-analysis.json` using `.build/analyze-hidden-vfx-state.py`: **1,106 objects, 245 references**, all resolved. The opponent has an empty deck, two hand entities still without CardDefId (50/51), two identified graveyard cards, and one identified banished card. The two hidden slots have no alternative identity, ability, informative cost/power, or components exposing them. `LocalGame` contains no alternative players, entities, or changes. The result branch contains only the local deck.

### Question status

- Explicit identity of the entire deck before reveals: **not demonstrated**.
- Another object/reference in final state supplying omitted identities: **not found in this state**.
- Additional identities in this match's VFX: known effects, without a complete deck list.
- Hidden-slot inference through generation/copying: **positive case for 50/51**, dependent on the documented ability.
- Limits: no memory reads or method-body decompilation; fields outside the sanitization allowlist remain masked. VfxBool.Bool boolean values also remain masked. These findings do not exclude other effects/channels.

Another generic match is not needed to confirm this result. Any new control should test a specific hypothesis. No further application code change, compilation, or upload occurred after capture 48; the analysis uses its scripts with self-checks.

Expanded audit of all strings: `.build/hidden-vfx-deep-analysis.json`, reproducible with `python3 .build/analyze_hidden_cards.py .build/network-hidden-vfx-capture.jsonl --deep-vfx --output OUTPUT_PATH`. It covered **651 VFX strings**: 160 sets of four ability fields, five LocationDefId values, three CardDefId values, and three names in DisabledCardVfx. Of 120 events with AbilityOwnerDefType Card, 114 point to already-identified cards (64 local, 50 opponent); the remaining six point to player entity 7 with definition Spell07NicoMinoru, not a hidden card. No ability source associated with a known card preceded its first reveal. Of 21 visual draws, **11 opponent draws arrived without identity**, while ten local draws already had identity. There are 30 visual events linked to still-unknown opponent entities, but their ability names belong to already-known sources; they must not be attributed to the target cards.

Additional false-positive control: record 14/change 0, `DisableVfx` has `DisabledCardVfx = [Lockheed, Gorr, GalactusFirstSteps]`, without an owner, target card, or zone. This is a global list of disabled effects, not evidence of three cards in the opponent's deck. The analyzer's self-check covers ordering before/after reveal, out-of-order context, local/global lists, numeric references, ability sources, and unidentified draws, and passed again after this audit.
