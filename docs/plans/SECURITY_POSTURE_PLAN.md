# Exnano Fabric Security Posture Plan

**Status:** Executed  
**Last executed:** 2026-07-14  
**Scope:** tracked source, Git history content, release binary, bundle resources, signing configuration, subprocess execution, persistence, dependencies, and release workflow

## Objectives

1. Prevent personal workstation paths, usernames, device names, consumer email addresses, and removable-volume paths from entering source or release artifacts.
2. Prevent credentials, private keys, API tokens, signing material, and notarization passwords from entering Git.
3. Reduce the data and capabilities exposed to Homebrew, Valet, and other child processes.
4. Produce release artifacts without local build-machine search paths or metadata.
5. Keep distribution signed, hardened, notarized, stapled, and Gatekeeper-verifiable.
6. Maintain a repeatable audit that can run before every release.

## Threat model

Fabric is intentionally a non-sandboxed developer tool because it executes Homebrew binaries, reads user LaunchAgent definitions, manages services, and reads their logs. Relevant threats include:

- command or argument injection;
- inherited environment secrets leaking to child processes;
- malicious or replaced executables in a user-writable Homebrew prefix;
- untrusted third-party taps or formulae;
- sensitive service credentials appearing in logs;
- over-broad filesystem access;
- stale build caches embedding local paths;
- private signing/notarization material committed to Git;
- unnotarized or modified release artifacts;
- unsafe service exposure beyond loopback;
- destructive database upgrades or data deletion.

## Executed audit checklist

### Repository and identity hygiene

- [x] Scanned tracked text for personal home/workspace paths, common device identifiers, removable-volume paths, SSH directories, and consumer email domains.
- [x] Scanned tracked text for private-key blocks and common token formats.
- [x] Scanned tracked filenames for environment files, private keys, certificates-with-private-material, provisioning profiles, and secrets directories.
- [x] Scanned Git history patches for local paths and secret-shaped values.
- [x] Reviewed Git remotes for embedded credentials.
- [x] Reviewed unique Git author identities.

**Result:** No personal development path, device path, consumer email, credential, private key, or token was found in tracked content or history patches. Git author name and corporate email remain in commit metadata as public provenance; they are not credentials. Rewriting that identity would require an explicit coordinated history rewrite and force-push, so it was not performed automatically.

A test fixture contains a synthetic `/Users/developer/...` LaunchAgent path. It is not tied to a real person, workstation, or device.

### Release artifact hygiene

- [x] Scanned release-binary strings for local paths, consumer emails, and secret-shaped values.
- [x] Inspected Mach-O load commands and runtime search paths.
- [x] Removed build-only Xcode/Developer toolchain rpaths from packaged binaries.
- [x] Removed metadata chunks from generated icon resources.
- [x] Confirmed only system Swift and loader-relative rpaths remain.
- [x] Confirmed app resources are sealed by code signing.
- [x] Confirmed stale module caches from the workspace rename were removed.
- [x] Added a mandatory clean step to the notarized distribution pipeline.

**Result:** The release binary contains no personal development path or detected secret. Generated icon resources contain no EXIF or PNG text metadata. Release builds no longer retain local Xcode toolchain search paths.

### Secret and key handling

- [x] Added ignore rules for key, PEM, PKCS#12, provisioning, environment, and secrets files.
- [x] Confirmed no signing private key is stored in the repository or app bundle.
- [x] Confirmed notarization credentials are read from a named Keychain profile.
- [x] Changed notarization setup documentation to use secure interactive prompts rather than placing an app-specific password in shell history.
- [x] Confirmed signing identity/profile names are supplied through environment variables.

**Result:** Private signing keys and notarization credentials remain in Keychain and are not present in the repository or release environment. The authorized profile was validated against Apple's notary service.

### Runtime process safety

- [x] Child processes use absolute executable URLs and argument arrays; no shell command strings are executed.
- [x] Formula identifiers reject option prefixes, path traversal, and unsupported characters.
- [x] Process output is bounded and command execution has timeout/cancellation behavior.
- [x] stdout and stderr use temporary files with private directory permissions, avoiding pipe deadlocks.
- [x] Replaced full parent-environment inheritance with a minimal allowlist.
- [x] Added a regression test proving unrelated parent variables are not inherited while explicitly requested values are forwarded.

**Result:** Homebrew and Valet commands no longer receive arbitrary Fabric/CI/signing environment variables. Tests pass for environment isolation.

### Persistence and filesystem

- [x] Registry writes are atomic.
- [x] Application Support directories use private permissions.
- [x] Registry files use owner-only permissions.
- [x] No credentials are intentionally persisted in the registry.
- [x] Service data deletion is not automatic.

**Result:** Current persisted state contains service metadata and local executable paths only. Future generated service credentials must use Keychain.

### Dependencies and supply chain

- [x] Reviewed Swift package dependencies.
- [x] Confirmed there are currently no external Swift package dependencies.
- [x] Confirmed Homebrew does not auto-update as a side effect of Fabric commands.
- [x] Confirmed Fabric does not silently add third-party taps.
- [x] Confirmed package pin ownership distinguishes pre-existing user pins from Fabric-created pins.

**Result:** Swift dependency exposure is minimal. Homebrew formulae and configured taps remain an external supply-chain boundary and must be shown clearly to users before installation.

### Service and network posture

- [x] Current endpoint defaults use loopback addresses in Fabric state.
- [x] Multiple ports are represented as named endpoints rather than identities.
- [x] Existing external Homebrew/Valet services are detected rather than silently claimed.
- [ ] Fabric-owned LaunchAgent adapters must enforce loopback binding in generated configuration.
- [ ] LAN exposure must require explicit confirmation and clear warnings.
- [ ] Adapter health checks must verify the expected process owns/responds on the configured endpoint.

### Logs and sensitive data

- [x] Fabric reads only explicitly discovered service log files.
- [x] The log viewer does not transmit logs or telemetry.
- [ ] Add adapter-specific redaction for credentials, API keys, connection URLs, and authorization headers.
- [ ] Add bounded log rotation for Fabric-owned LaunchAgents.
- [ ] Diagnostic exports must redact paths, usernames, credentials, and tokens by default.

### Signing and distribution

- [x] Distribution script enables hardened runtime and timestamped Developer ID signing.
- [x] Distribution script verifies the code signature.
- [x] Distribution script submits through `notarytool`, waits for acceptance, staples, validates, and runs Gatekeeper assessment.
- [x] Installation into `~/Applications` happens only after successful notarization and validation.
- [x] Create the authorized `notarytool` Keychain profile and execute a successful notarized distribution.
- [x] Record the release ZIP checksum for the notarized artifact.

**Release 0.1.2 evidence:** Apple accepted submission `6a4f5df7-d193-4849-b03d-60d338a50ad2`. Stapling, Gatekeeper assessment, installed-bundle signature verification, and ticket validation passed. SHA-256 for `Exnano-Fabric-0.1.2.zip`: `d811017693c8cb72308a7866e4c8fce3e0ffed45cb41fbda46759dc9e93a5375`.

## Remediations completed during this execution

1. Removed complete parent-environment inheritance from subprocesses.
2. Added a serialized environment-isolation regression test.
3. Removed local Xcode/Developer rpaths from packaged binaries.
4. Cleaned stale module caches containing the previous workspace location.
5. Added clean builds to the notarized distribution workflow.
6. Stripped metadata from generated icon resources.
7. Removed password arguments from notarization documentation.
8. Expanded ignored sensitive-file patterns.
9. Added `scripts/security-audit.sh` and `make security-audit`.

## Repeatable verification

Run before each release:

```bash
swift test
./scripts/build-app.sh release
make security-audit
codesign --verify --deep --strict "dist/Exnano Fabric.app"
```

For a distribution candidate, additionally run:

```bash
make distribute
```

The distribution command must fail closed if the Developer ID identity or notarization Keychain profile is unavailable.

## CI and governance follow-ups

### Priority 0 — release verification

- [x] Create and validate the notarization Keychain profile on the authorized release machine.
- [x] Run `make distribute` and retain Apple notarization evidence.
- [ ] Verify Start at login using the installed, stable bundle path.
- [ ] Decide whether the current public Git author identity is acceptable; if not, coordinate a history rewrite and force-push with all collaborators.

### Priority 1 — before Fabric-owned service instances

- [ ] Add Keychain storage and rotation for generated database/API credentials.
- [ ] Implement adapter-level config validation and secret redaction.
- [ ] Verify exact Cellar executable real paths and versions before every start.
- [ ] Add package/tap trust confirmation for non-core sources.
- [ ] Add safe backup and migration gates for database upgrades.

### Priority 2 — before `1.0.0`

- [ ] Run a maintained secret scanner such as Gitleaks in CI and across full history.
- [ ] Add static analysis and dependency vulnerability checks to CI.
- [ ] Add signed release checksums and build provenance.
- [ ] Add a documented vulnerability-reporting and incident-response process.
- [ ] Perform a focused threat-model review of LaunchAgent plist generation and log access.

## Security incident response

If a secret or personal path is discovered:

1. Stop distribution and disable affected automation.
2. Revoke or rotate the credential first; deleting Git content is not sufficient.
3. Remove the value from the current tree.
4. Decide whether history rewriting is necessary based on exposure and repository visibility.
5. Rebuild from a clean checkout.
6. Re-sign, re-notarize, and replace affected artifacts.
7. Document the incident without reproducing the secret.
