# Releasing Fabric

Fabric uses semantic versioning:

- `MAJOR`: incompatible product or persistence behavior requiring explicit migration;
- `MINOR`: a feature release or newly supported service adapter;
- `PATCH`: backward-compatible fixes;
- build number: monotonically increasing for every distributed artifact.

`Config/Version.json` is the source of truth for marketing version, build number, and persistence schema version.

## One-time signing and notarization setup

Fabric's release pipeline reads credentials from the login keychain and environment. Never commit Apple credentials or app-specific passwords.

Store a notarization profile once:

```bash
xcrun notarytool store-credentials "exnano-fabric"
```

`notarytool` securely prompts for the Apple ID, Team ID, and app-specific password without placing them in shell history.

Then export the certificate identity and profile name for the release shell:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Organization (TEAMID)"
export NOTARYTOOL_PROFILE="exnano-fabric"
```

## Prepare a release

```bash
./scripts/bump-version.sh minor  # or major, patch, build
swift test
make distribute
```

`make distribute` performs a release build, enables the hardened runtime, applies a timestamped Developer ID signature, submits a ZIP to Apple, waits for acceptance, staples and validates the ticket, runs Gatekeeper assessment, and copies the final app to `/Applications/Exnano Fabric.app`.

Then:

1. Update `docs/MASTER_PLAN.md` progress.
2. Update `README.md` for every feature release.
3. Add a dated section to `CHANGELOG.md`.
4. Manually launch `/Applications/Exnano Fabric.app` and verify menu-bar/window and Start at login behavior.
5. Commit the release metadata.
6. Create an annotated `v<version>` tag only when the release is approved.

Do not reuse build numbers. Do not change the persistence schema version merely because the app version changes; increment it only when stored data changes and a migration exists.
