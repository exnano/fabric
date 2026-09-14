# Exnano Fabric Security Posture Plan

**Status:** Execution completed with open findings; archived audit record, NOT distribution approval  
**Last executed:** 2026-09-14  
**Previous execution:** 2026-07-14 (historical evidence retained below)  
**Scope:** current working tree including untracked implementation files, Git history content, release binary, bundle resources, signing configuration, subprocess execution, persistence, dependencies, and release workflow

## 2026-09-14 execution results

The audit execution is complete. Remediation of the findings below is **not** complete. Archiving this report records the completed assessment; it does not waive open release gates or certify the app as secure.

### Candidate and reproducibility

- Git base: `33d4a16`, with uncommitted tracked changes and three untracked implementation/test files at the start of the audit. This is a working-tree assessment, not a clean tagged release.
- Candidate: `dist/Exnano Fabric.app`, version **0.1.4 (build 5)**, rebuilt during this execution. The build was incremental, not a clean distribution build.
- Executable SHA-256: `c1edfc417cff81dd9f3c4c96a61eb393558177856b59dce92b85c822d31b1bdb`. This identifies `Contents/MacOS/Fabric` only, not a ZIP or the complete bundle.
- Candidate signature: **ad-hoc**, `flags=0x2(adhoc)`. No Developer ID authority, hardened-runtime flag, or secure timestamp was established for this candidate.
- Runtime search paths: `/usr/lib/swift` and `@loader_path`.
- The installed app was inspected read-only during review and also reported 0.1.4 (5), ad-hoc. This execution did not replace it; identical version labels do not prove identical content.

### Verification matrix

| Check | Current result and limits |
|---|---|
| `swift test` | Passed: 28 tests across 7 suites. Includes fake-runner migration permissions, cleanup, capability, and concurrency coverage; not a live migration/authentication test. |
| `./scripts/build-app.sh release` | Passed; produced the candidate above. |
| `make security-audit` | Exit 0 after the build. Output captured and sanitized to avoid copying identity values or potential secrets into the report. Pass is limited to the script's patterns/exclusions and does not close scanner defects below. |
| `codesign --verify --deep --strict --verbose=2` | Passed on the freshly rebuilt candidate. Confirms signature consistency, not Developer ID distribution approval. |
| Mach-O runtime search paths | Inspected on fresh candidate; no local developer-toolchain rpaths observed. |
| Broader repository/history pattern review | No matches for configured secret/email patterns. Additional path hits were scanner literals and two vendored upstream example paths in `.agents/skills/swiftui-ui-patterns/references/scroll-reveal.md`. Do not claim there are no personal-looking paths anywhere in history. Values intentionally omitted. |
| Untracked files | Supplemental reviewer scan covered all three untracked Swift files present at audit start; no configured pattern matches. Standard `git grep` does not cover them. |
| Sensitive filenames | Current tracked filenames had no configured matches. Deleted historical sensitive filenames are not covered by the standard audit. |
| Git remotes and identity | One remote reviewed; no HTTP userinfo detected. One unique author identity reviewed without copying personal values. No identity changes or history rewrite. |
| Bundle resources | Reviewer string scan found no configured pattern matches in four other existing bundle files. Decoded asset/EXIF metadata was not independently verified; do not renew the historical metadata-cleanliness claim. |
| Script syntax/dependencies | Reviewer syntax checks passed for build, distribution, and audit scripts. No external Swift package dependencies declared. |
| Runtime/persistence/UI | Four read-only review workstreams completed; findings below. Private registry writes, process environment allowlisting, argument arrays, Keychain storage, and fixed warning summaries remain useful safeguards. |
| Notarization/stapling/Gatekeeper | Not run for this candidate. Historical acceptance applies only to the historical artifacts below. |
| Live authentication, listening addresses, login item, migration and backup | Not exercised. No service mutations, Keychain retrieval, credential rotation, or destructive database operations performed. |

### Open findings and required follow-up

Paths below are repository-relative. Findings are based on source inspection; exploitability and actual migration failure were not live-tested.

| ID / priority | Evidence | Impact and required follow-up |
|---|---|---|
| SEC-01 / High | `Sources/FabricCore/Infrastructure/Homebrew/HomebrewClient.swift`: `runMeilisearchService`, `setLaunchEnvironment`, cleanup | Normal start/restart publishes the master key through session-wide `launchctl setenv` and secret-bearing argv. Redacting the display command does not protect either boundary. Cleanup failures are ignored and the key is not durable across login/external restart. Replace with verified service-scoped delivery; distinguish stored from verified-active credentials. The new migration path avoids global injection but does not fix normal starts. |
| SEC-02 / High | `MeilisearchDatabaseUpgrader.swift`: `launch` | The updater accepts an absolute executable with self-reported flag support from a user LaunchAgent, then releases a Keychain credential to it. Canonical expected keg/version, plist symlinks, label identity, ownership, and tap identity are not established. Validate the intended service and executable before executing preflight or releasing credentials; add substitution/symlink/label tests. This requires a local configuration or supply-chain attacker, not an unauthenticated remote caller. |
| SEC-03 / High | `MeilisearchDatabaseUpgrader.swift`: copied job configuration; `HomebrewClient.upgradeMeilisearchDatabase`; `AppModel.upgradeMeilisearchDatabase` | The loaded migration job can retain `KeepAlive` and automatically relaunch with the flag. Busy guards expire at bootstrap acceptance, so Stop, Restart All, package changes, or another migration can interrupt unfinished work. Disable automatic migration retries and track an in-progress/outcome-unknown state across app restarts until completion or explicit recovery. Current tests do not prove migration-lifetime exclusion. |
| SEC-04 / High | `Sources/FabricCore/Application/FabricRuntime.swift`: `addService`, `performPackageAction` | Load–await–save workflows can overwrite concurrent registry updates. Atomic JSON writes do not prevent lost registrations/metadata. Add transactional or revision-checked mutations and deterministic interleaving tests. This does not itself delete service databases. |
| SEC-05 / Medium | `scripts/security-audit.sh` | Broad exclusions omit plans and vendored skills, artifact scanning checks only the main executable, untracked files and historical sensitive filenames are absent, missing binaries are silently skipped, and `|| true` masks tool failures. Failure details can print actual secret matches. Make release mode fail closed, scan the complete candidate and relevant source/history, narrow exceptions, and report locations/rule IDs without values. A current pattern pass is not comprehensive secret scanning. |
| SEC-06 / Medium; distribution blocker | `scripts/distribute-app.sh` | The pipeline does not enforce the audit against its rebuilt final candidate, deletes its temporary submission ZIP, does not retain final stapled archive/checksum/provenance, and removes the installed app before validating replacement. Gate the exact candidate, retain final evidence, and stage installation with recovery. Fresh Developer ID signing, hardened runtime, notarization, stapling, and Gatekeeper verification are required before external distribution of 0.1.4. |
| SEC-07 / Medium | `Features/Logs/LogViewer.swift`; `HomebrewClient.requireSuccess`; `AppModel.present` | Raw selectable logs and subprocess errors may expose credentials, authorization headers, URLs, or workstation paths. The viewer's initial tail seek followed by `readToEnd()` does not enforce the stated read bound under concurrent growth. Add shared redaction and bounded reads with tests. Local display is not telemetry, but screenshots and copied diagnostics can leak content. |
| SEC-08 / Medium | `Features/ServiceList/ServiceRowView.swift`: master-key sheet; `HomebrewClient.setMeilisearchMasterKey` | Clipboard copies are plaintext without expiry; rotation lacks prominent client-invalidation/durability warnings. Keychain is changed before restart succeeds, and conflicting job credentials can leave saved and active keys different. Disclose clipboard exposure, implement conditional cleanup, distinguish storage/restart/authentication outcomes, and verify effective rotation. |
| SEC-09 / Medium | `MeilisearchDatabaseUpgrader.swift`: database-path preflight | Existing-directory validation does not prove the intended database or supported source version; even an empty directory passes. Backup verification is user acknowledgment only. Validate database identity/version and bind a verified backup to that identity before treating migration as safely gated. |

### Disposition and remaining gates

- [x] Execute and record automated checks on the rebuilt development candidate.
- [x] Review current runtime, app, persistence, and release boundaries, including untracked additions.
- [x] Separate historical release evidence from current validation.
- [x] Record findings without reproducing credentials, personal identities, or upstream personal-path values.
- [x] Archive this completed execution report under `docs/plans/archives` and update its README reference.
- [ ] Remediate SEC-01 through SEC-04 before relying on secure credential delivery or reliably guarded migrations.
- [ ] Remediate scanner/release-gate findings and re-audit the exact distribution candidate.
- [ ] Complete fresh Developer ID/notarization/Gatekeeper validation and retain final artifact provenance.
- [ ] Complete controlled live authentication, migration, network-binding, and login-item verification with explicit authorization and backups.

No runtime fixes, commits, pushes, history rewrites, notarization submissions, or live service changes were made as part of this audit execution. Future product work and the historical unchecked roadmap items below remain open.

---

## Historical execution — 2026-07-14

**Everything below records the prior execution and its roadmap. Its checked boxes and result statements are historical claims, not renewed guarantees for the current candidate.** Where they differ, the 2026-09-14 matrix and open findings above govern the current assessment.

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
- [x] Installation into global `/Applications` happens only after successful notarization and validation.
- [x] Create the authorized `notarytool` Keychain profile and execute a successful notarized distribution.
- [x] Record the release ZIP checksum for the notarized artifact.

**Release 0.1.2 evidence:** Apple accepted submission `6a4f5df7-d193-4849-b03d-60d338a50ad2`. Stapling, Gatekeeper assessment, installed-bundle signature verification, and ticket validation passed. SHA-256 for `Exnano-Fabric-0.1.2.zip`: `d811017693c8cb72308a7866e4c8fce3e0ffed45cb41fbda46759dc9e93a5375`.

**Release 0.1.3 evidence:** Apple accepted submission `686acebc-efdd-417e-ac28-3984fa387100`. The globally installed bundle passed signature, staple, and Gatekeeper validation. SHA-256 for `Exnano-Fabric-0.1.3.zip`: `f22eaaea1db3a491f67bea48dec58ed6caad0657ff10a719813f9411b2cbfa9f`.

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
