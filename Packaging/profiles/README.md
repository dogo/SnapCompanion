# Provisioning profiles

`build_app.sh` embeds these into the app + system extension so the restricted
Network Extension entitlement is authorized (required even for Developer ID).
The files are git-ignored (`*.provisionprofile`) — each developer supplies their own.

Create both **Developer ID** profiles in the Apple Developer portal, then export
them here with these exact names:

- `SnapCompanion.provisionprofile` — App ID `br.com.anykey.SnapSync`
- `SnapCompanionProxy.provisionprofile` — App ID `br.com.anykey.SnapSync.proxy`

## Portal steps

1. Certificates, IDs & Profiles → **Identifiers** → for **both** App IDs above,
   enable the **Network Extensions** capability and save.
2. **Profiles** → **+** → **Developer ID** distribution → pick the App ID →
   your Developer ID Application cert → download.
3. Rename/drop the two files here with the names above.

Then: `SNAPSYNC_SIGNING_IDENTITY="Developer ID Application: … (75C4E36ZA7)" ./scripts/build_app.sh`
