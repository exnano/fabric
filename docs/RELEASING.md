# Releasing Fabric

Fabric uses semantic versioning:

- `MAJOR`: incompatible product or persistence behavior requiring explicit migration;
- `MINOR`: a feature release or newly supported service adapter;
- `PATCH`: backward-compatible fixes;
- build number: monotonically increasing for every distributed artifact.

`Config/Version.json` is the source of truth for marketing version, build number, and persistence schema version.

## Prepare a release

```bash
./scripts/bump-version.sh minor  # or major, patch, build
swift test
make app
codesign --verify --deep --strict "dist/Exnano Fabric.app"
```

Then:

1. Update `docs/MASTER_PLAN.md` progress.
2. Update `README.md` for every feature release.
3. Add a dated section to `CHANGELOG.md`.
4. Manually launch the bundle and verify menu-bar/window behavior.
5. Commit the release metadata.
6. Create an annotated `v<version>` tag only when the release is approved.

Do not reuse build numbers. Do not change the persistence schema version merely because the app version changes; increment it only when stored data changes and a migration exists.
