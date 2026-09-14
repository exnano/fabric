# Exnano Fabric

**Fabric** is a native macOS SwiftUI menu-bar application for installing, pinning, and managing local development services provided by Homebrew. The distributed application name is **Exnano Fabric.app**.

> Current version: **0.1.4 (build 5)** — service warning details, Homebrew metadata refresh, and confirmed Restart All.

## Current capabilities

- Opens its native service-management window automatically at launch.
- Shows a branded Dock icon while the management window is open, with light and dark variants that follow macOS appearance.
- Keeps a menu-bar control available and stays running when the management window closes.
- Uses Command-Q to close the management window without terminating Fabric.
- Provides a Start at login checkbox backed by macOS Login Items; unchecking removes the registration.
- Lists all configured services, endpoints, statuses, and Start/Stop/Restart actions in the menu-bar dropdown.
- Discovers supported versioned formulae from the user's actual Homebrew catalog.
- Installs a selected formula without automatically running `brew update`.
- Pins the installed formula so normal Homebrew upgrades do not move it unexpectedly.
- Lets users lock or unlock a registered formula and run an explicit, confirmed Homebrew upgrade.
- Restores the prior pin after an upgrade and tracks whether a pin belonged to the user before Fabric touched it.
- Stores Meilisearch master keys in macOS Keychain, with secure reveal, copy, generation, and restart controls.
- Restarts Meilisearch with `--upgrade-db` on demand after an explicit snapshot/migration warning.
- Lists added services with source, version, endpoints, and status.
- Orders services consistently by localized name, then status when names match.
- Starts, stops, and restarts services.
- Provides a confirmed Restart All toolbar action for all added services, including stopped ones; restarts run sequentially and failures are reported together.
- Opens service logs when Homebrew/Valet exposes readable log paths.
- Persists registrations under `~/Library/Application Support/Exnano Fabric/services.json`.
- Detects installed PHP-FPM, Nginx, Caddy, and Laravel Valet integrations rather than offering to install them.

## Warning details and Homebrew upgrades

Click a service's status badge to see its full explanation and open its logs. Warning rows show Homebrew's status and exit code directly. When readable recent logs contain a recognized startup error, Fabric adds a **possible cause**, such as an incompatible Meilisearch database, an occupied port, insufficient permissions, or a full disk. Log clues may be stale; verify the latest timestamps before restarting or migrating. Fabric does not automatically repair or migrate services.

To include a service in normal Homebrew upgrades:

1. Choose **Unlock Version** in its package menu. This removes the actual Homebrew pin.
2. Run `brew upgrade` in Terminal, or target one formula—for example, `brew upgrade meilisearch`.
3. Click **Refresh** in Fabric, or wait for the next automatic refresh. Installed versions and pin states are read from Homebrew, including changes made outside Fabric.

`brew list --pinned` shows packages that normal upgrades will skip. Versioned formulae such as `postgresql@17` stay on that formula's major line; upgrading them does not switch to a different formula. Back up databases before upgrading.

The displayed version is installed package metadata, not a query of the running server. A restart or service-specific database migration may still be necessary. If metadata cannot be refreshed, Fabric shows a notice and keeps the saved values without changing the independently observed service status. Refresh never pins, unpins, upgrades, or restarts services and never runs `brew update`.

**Existing Meilisearch limitation:** master-key startup injection is not yet durable across login or external Homebrew restarts. Verify authentication after restarting or upgrading Meilisearch; this change does not repair that launch mechanism.

### Meilisearch database upgrades

After creating a snapshot and waiting for its task to succeed, install the intended Meilisearch binary using Homebrew. Then choose **Upgrade Database…** from the Meilisearch package menu and confirm that your backup is verified.

Fabric checks the configured executable's `--help` for exact `--upgrade-db` support (available since v1.51) and requires an explicit existing database directory. It preserves the user Homebrew LaunchAgent's database arguments, working directory, and logs, then unloads that job and registers a temporary, service-scoped job with `--upgrade-db`. The temporary plist is private (`0700` directory, `0600` file) and deleted after launch registration; the original LaunchAgent remains unchanged. When a Fabric master key exists, this migration launch passes it through the job environment, not command arguments or global launchd environment. Normal restart credential limitations described above still apply.

A successful launch request is **not** a completed migration. Follow `GET /tasks?types=UpgradeDatabase` and then `GET /tasks/TASK_UID`, with appropriate authentication, until the task succeeds. Check the latest logs if startup fails. Do not restart during migration. Fabric does not create or verify snapshots, poll upgrade tasks, retry migrations, or roll back databases automatically. The loaded migration flag lasts for that job registration, including automatic process restarts; a normal Homebrew restart or login uses the unchanged original plist.

Databases older than v1.12 require dump migration. Unsupported binaries fail preflight without stopping the service; Fabric does not silently substitute an experimental flag. See [Meilisearch's upgrade guide](https://www.meilisearch.com/docs/resources/migration/updating#updating-with-the-upgrade-db-flag).

## Supported service catalog

| Service | `0.1.x` behavior | Target behavior |
|---|---|---|
| MariaDB versions | Discover/install/pin; singleton `brew services` management | Isolated instances and data directories |
| MySQL versions | Discover/install/pin; singleton `brew services` management | Isolated instances and data directories |
| PostgreSQL versions | Discover/install/pin; singleton `brew services` management | Isolated clusters with major-version safeguards |
| Redis versions | Discover/install/pin; singleton `brew services` management | Multiple Fabric LaunchAgents and ports |
| Valkey versions | Discover/install/pin; singleton `brew services` management | Multiple Fabric LaunchAgents and ports |
| Meilisearch versions | Discover/install/pin; Keychain master key and `--upgrade-db` restart | Isolated databases, keys, and ports |
| Typesense versions | Discovers formulae from already configured taps | Validated trusted source and isolated instances |
| Mailpit | Discover/install/pin; SMTP and web endpoints shown | Multiple isolated SMTP/web port pairs |
| RustFS | Discovers formulae from already configured taps | Validated trusted source and isolated instances |
| PHP-FPM | Detect installed Homebrew PHP formulae and manage their service | Isolated FPM pools by PHP version |
| Laravel Valet | Detect common Composer-global installs; start/stop/restart/status | Broader Composer detection and conflict diagnostics |
| Nginx | Detect installed formulae and manage their Homebrew service | Config/log diagnostics; isolation decision pending |
| Caddy | Detect installed formulae and manage their Homebrew service | Config/log diagnostics; isolation decision pending |

### Important `0.1.x` limitation

Homebrew generally exposes one `brew services` LaunchAgent per formula. Fabric therefore rejects duplicate registrations of the same formula in this release. It does **not** pretend that changing a displayed port creates an isolated instance.

True multiple instances—each with a stable UUID, independent config/data/logs, a Fabric-owned LaunchAgent, and automatically selected free ports—are the primary goal of `0.2.0`. See [`docs/MASTER_PLAN.md`](docs/MASTER_PLAN.md).

## Requirements

- macOS 15 or newer
- Xcode/Swift toolchain capable of Swift 6.2+
- Homebrew at `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`

Fabric is intentionally not sandboxed in the current development build because it must execute Homebrew and inspect/manage user LaunchAgents.

## Build and run

Open `ExnanoFabric.xcodeproj` in Xcode and select the **Exnano Fabric** scheme. The management-window Canvas preview lives in `Sources/FabricApp/PreviewSupport/ServiceListPreview.swift` and uses in-memory fixtures without invoking Homebrew.

Regenerate the project after changing `project.yml` or target membership:

```bash
brew install xcodegen
./scripts/generate-xcode-project.sh
```

The SwiftPM and command-line release workflow remains available:

```bash
swift build
swift test
make app
open "dist/Exnano Fabric.app"
```

For a one-command debug build and launch:

```bash
make run
```

`make app` creates an ad-hoc signed development bundle. `make distribute` creates a hardened Developer ID build, submits it for Apple notarization, staples the ticket, and installs it globally as `/Applications/Exnano Fabric.app`; see [`docs/RELEASING.md`](docs/RELEASING.md) for credential setup.

## Versioning

`Config/Version.json` is the single source of truth:

```json
{
  "marketingVersion": "0.1.0",
  "buildNumber": 1,
  "persistenceSchemaVersion": 1
}
```

Bump versions with:

```bash
./scripts/bump-version.sh patch
./scripts/bump-version.sh minor
./scripts/bump-version.sh major
./scripts/bump-version.sh build
```

Every feature release must update this README, the master plan, and `CHANGELOG.md`. See [`docs/RELEASING.md`](docs/RELEASING.md).

## Project structure

```text
Sources/
├── FabricApp/              # SwiftUI/AppKit menu bar and window shell
└── FabricCore/
    ├── Application/        # Service workflows and backend boundaries
    ├── Domain/             # Sendable models and status/catalog vocabulary
    └── Infrastructure/     # Homebrew, process execution, persistence
Tests/FabricCoreTests/      # Swift Testing suites
docs/                       # Architecture, releases, and phased master plan
scripts/                    # App bundling, launch, and version tools
```

## Safety model

- No shell command interpolation; executables receive argument arrays.
- Child processes receive a minimal allowlisted environment instead of Fabric's complete environment.
- No automatic `brew update`.
- No `sudo` for Homebrew operations.
- No silent third-party tap installation.
- No automatic removal of packages, pins, or service data.
- Services should bind to loopback by default in the Fabric-owned runtime.
- Database major upgrades will require explicit compatibility and backup workflows.

Run the repeatable repository and release-binary checks with:

```bash
make security-audit
```

The security audit executed on 2026-09-14 is archived in [`docs/plans/archives/SECURITY_POSTURE_PLAN.md`](docs/plans/archives/SECURITY_POSTURE_PLAN.md). The execution is complete **with open findings**, not distribution approval; the report records current verification, historical release evidence, and remaining remediation/release gates.

## Development status

Fabric is pre-release software. `0.1.1` includes the native app, package locking, persistence, Homebrew bridge, menu-bar controls, login-item management, and release hardening. The detailed roadmap and managed todo list live in [`docs/MASTER_PLAN.md`](docs/MASTER_PLAN.md); architectural decisions live in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
