# Exnano Fabric Master Plan

This document is the source of truth for feature scope and progress. Keep checkboxes current in the same pull request or commit that changes a feature.

## Product principles

- **Homebrew owns packages.** Fabric discovers, installs, and pins formulae without modifying Homebrew itself.
- **Fabric owns isolated instances.** The target runtime uses one user LaunchAgent, data directory, configuration set, and log directory per instance.
- **launchd owns process lifetime.** Services continue to run when the Fabric window is closed or the app exits.
- **Adapters own service semantics.** Initialization, foreground arguments, health checks, shutdown, and upgrades differ by service family.
- **Safe defaults first.** Bind to loopback, never invoke a shell, never run Homebrew with `sudo`, never auto-update Homebrew, and never delete service data by default.
- **Ports are attributes, not identities.** Every instance has a stable UUID and one or more named endpoints.

## Status legend

- [x] Complete and included in the current codebase
- [ ] Planned or in progress
- **Release gate:** all listed gate items must be complete before the release version changes

---

## Phase 0 — Repository and architecture foundation (`0.1.0`) ✅

- [x] Initialize Git with a `main` branch and use focused commits.
- [x] Create the Swift 6 package with a testable `FabricCore` module.
- [x] Establish the product name **Exnano Fabric.app** and short name **Fabric**.
- [x] Add semantic marketing version, monotonic build number, and persistence schema version.
- [x] Add deterministic local `.app` bundle generation and ad-hoc signing.
- [x] Define service families, package locks, named endpoints, runtime status, and sort models.
- [x] Add a safe process runner using absolute executable paths and argument arrays.
- [x] Add versioned, atomic JSON persistence under Application Support.
- [x] Add unit tests for core parsing, persistence, and workflows.

**Release gate:** `swift test` and `make app` pass on Apple Silicon macOS.

## Phase 1 — Homebrew bridge and native dashboard (`0.1.0`) ✅

- [x] Run as a native menu-bar utility with a reopenable management window.
- [x] Keep the process alive when the management window closes.
- [x] Show service name, formula/source, version, endpoints, and Offline/Running/Warning status.
- [x] Sort by name or status in ascending or descending order.
- [x] Add Start, Stop, and Restart actions.
- [x] Discover logs from Homebrew LaunchAgent plists and detected Valet logs.
- [x] Discover available versioned formulae dynamically with `brew formulae`.
- [x] Install formulae without running `brew update`.
- [x] Pin the installed formula and record whether Fabric or the user owned the pin.
- [x] Persist added services between launches.
- [x] Detect installed Homebrew PHP/php-fpm formulae.
- [x] Detect Laravel Valet in common Composer global locations.
- [x] Detect installed Nginx formulae.
- [x] Detect installed Caddy formulae.
- [x] Manage detected PHP-FPM, Nginx, Caddy, and Valet through their existing service commands.
- [x] Reject duplicate formula registrations while using `brew services`.
- [ ] Add remove/unregister UI without deleting package data or user-owned pins.
- [ ] Add a settings screen for a custom Homebrew executable path.
- [ ] Show clearer diagnostics when another manager owns a conflicting service.

**Known limitation:** `brew services` exposes one launchd job per formula. Version `0.1.x` therefore supports one Fabric registration per formula. It does not claim to provide isolated multi-instance execution.

## Phase 2 — Fabric LaunchAgent runtime pilot (`0.2.0`)

- [ ] Define the version-aware `ServiceAdapter` protocol.
- [ ] Create one per-user LaunchAgent label per instance: `com.exnano.fabric.<service>.<id>`.
- [ ] Store instance state under `~/Library/Application Support/Exnano Fabric/Instances/<uuid>/`.
- [ ] Store logs under `~/Library/Logs/Exnano Fabric/<uuid>/`.
- [ ] Render LaunchAgent plists atomically with exact Cellar executable paths.
- [ ] Use `launchctl bootstrap`, `bootout`, `print`, and controlled `kickstart` in `gui/<uid>`.
- [ ] Add foreground process supervision and graceful stop timeouts.
- [ ] Add crash-loop throttling and actionable Warning states.
- [ ] Add a race-aware loopback port allocator with named multi-port reservations.
- [ ] Check both launchd state and adapter readiness before reporting Running.
- [ ] Detect and block conflicts with `homebrew.mxcl.*`, Valet, and manually managed jobs.
- [ ] Implement the Mailpit adapter (SMTP + web endpoints).
- [ ] Implement the Redis adapter.
- [ ] Implement the Valkey adapter.
- [ ] Allow multiple instances of the same package version with independent ports.
- [ ] Keep instances running independently of the Fabric app process.

**Release gate:** create, start, stop, restart, recover, and remove two instances of each pilot service without shared data/config/ports.

## Phase 3 — Search and object services (`0.3.0`)

- [ ] Implement the Meilisearch adapter with database path and optional master key.
- [ ] Store generated secrets in Keychain and redact them from logs.
- [ ] Validate a trusted Typesense formula/tap source.
- [ ] Implement the Typesense adapter with API key and data compatibility checks.
- [ ] Validate a trusted RustFS formula/tap source.
- [ ] Implement the RustFS adapter with separately named API/console endpoints.
- [ ] Require explicit approval before using any third-party tap.
- [ ] Add service-specific connection summaries and copy actions.
- [ ] Add bounded log retention and rotation.

**Release gate:** adapter compatibility is tested against every version shown as supported in the catalog.

## Phase 4 — Relational databases (`0.4.0`)

- [ ] Implement PostgreSQL cluster initialization and readiness checks.
- [ ] Treat PostgreSQL major version as a data compatibility boundary.
- [ ] Add explicit PostgreSQL backup/restore or `pg_upgrade` workflows.
- [ ] Implement MySQL initialization, authentication defaults, and readiness checks.
- [ ] Implement MariaDB separately from MySQL; never share their data directories.
- [ ] Add graceful database shutdown with a force-stop warning path.
- [ ] Add backup-before-upgrade gates.
- [ ] Add version-aware upgrade validation; never automate a database major upgrade silently.
- [ ] Support multiple isolated versions and instances concurrently.

**Release gate:** destructive upgrade and deletion paths require explicit confirmation and preserve recoverable data by default.

## Phase 5 — PHP and local web stack (`0.5.0`)

- [ ] Implement isolated PHP-FPM pools with generated config and loopback FastCGI ports.
- [ ] Support multiple installed Homebrew PHP versions concurrently.
- [ ] Improve Valet detection through Composer metadata, not only common paths.
- [ ] Keep Valet as an externally managed environment integration initially.
- [ ] Add Valet start/stop/restart/status compatibility tests.
- [ ] Add Nginx configuration and log diagnostics.
- [ ] Add Caddy configuration and log diagnostics.
- [ ] Detect Nginx/Caddy/Valet port ownership conflicts before starting instances.
- [ ] Decide whether isolated Fabric-owned Nginx/Caddy instances belong in `0.5` or a later web-proxy phase.

**Release gate:** Fabric never edits a user's Valet, Nginx, Caddy, or PHP configuration without preview and confirmation.

## Phase 6 — Operations and recovery (`0.6.0`)

- [ ] Add instance export/import without secrets.
- [ ] Add archive data vs. permanently delete flows.
- [ ] Add stale package-lock and missing-keg repair workflows.
- [ ] Detect external unpin, upgrade, cleanup, and binary replacement.
- [ ] Add explicit package upgrade transactions with rollback guidance.
- [ ] Add per-instance environment/config previews.
- [ ] Add notification support for unexpected exits.
- [ ] Add launch-at-login controls for Fabric and individual instances.
- [ ] Add diagnostic bundle export with secret redaction.

## Phase 7 — Distribution hardening (`0.8.0`)

- [ ] Move the thin app shell to a conventional Xcode app target while retaining `FabricCore`.
- [ ] Add branded app/menu-bar icons and accessibility labels.
- [ ] Add Developer ID signing, hardened runtime, notarization, and Sparkle/update-channel evaluation.
- [ ] Add CI for build, tests, bundle validation, and release artifacts.
- [ ] Add UI tests for menu-bar lifecycle and singleton management window behavior.
- [ ] Add accessibility, localization, and VoiceOver audit.
- [ ] Add performance tests for large service lists and logs.
- [ ] Complete threat model and dependency/source trust documentation.

## Phase 8 — Stable release (`1.0.0`)

- [ ] Complete all advertised adapter compatibility matrices.
- [ ] Complete data migration and backward-compatible persistence tests.
- [ ] Publish backup, recovery, and uninstall documentation.
- [ ] Select and publish the project license.
- [ ] Publish signed and notarized release artifacts.
- [ ] Update README feature matrix to contain no ambiguous “supported” claims.

---

## Release checklist

Every feature release (`0.x.0` or `x.0.0`) must include all of the following:

- [ ] Update `Config/Version.json` using `scripts/bump-version.sh`.
- [ ] Update this master plan's checkboxes and release mapping.
- [ ] Update `README.md` capabilities, limitations, supported-service matrix, and build instructions.
- [ ] Add a dated entry to `CHANGELOG.md`.
- [ ] Run `swift test`.
- [ ] Run `make app` and verify the generated bundle with `codesign --verify --deep --strict`.
- [ ] Manually verify menu-bar launch, management-window reopen, and Quit.
- [ ] Tag the release as `v<marketingVersion>` only after the release commit is reviewed.
