# Exnano Fabric

**Fabric** is a native macOS SwiftUI menu-bar application for installing, pinning, and managing local development services provided by Homebrew. The distributed application name is **Exnano Fabric.app**.

> Current version: **0.1.0 (build 1)** — foundation/Homebrew bridge release.

## Current capabilities

- Opens its native service-management window automatically at launch.
- Shows a Dock icon while the management window is open, then returns to menu-bar-only mode when it closes.
- Keeps a menu-bar control available and stays running when the management window closes.
- Lists all configured services, endpoints, statuses, and Start/Stop/Restart actions in the menu-bar dropdown.
- Discovers supported versioned formulae from the user's actual Homebrew catalog.
- Installs a selected formula without automatically running `brew update`.
- Pins the installed formula so normal Homebrew upgrades do not move it unexpectedly.
- Tracks whether a pin belonged to the user before Fabric touched it.
- Lists added services with source, version, endpoints, and status.
- Orders services consistently by localized name, then status when names match.
- Starts, stops, and restarts services.
- Opens service logs when Homebrew/Valet exposes readable log paths.
- Persists registrations under `~/Library/Application Support/Exnano Fabric/services.json`.
- Detects installed PHP-FPM, Nginx, Caddy, and Laravel Valet integrations rather than offering to install them.

## Supported service catalog

| Service | `0.1.x` behavior | Target behavior |
|---|---|---|
| MariaDB versions | Discover/install/pin; singleton `brew services` management | Isolated instances and data directories |
| MySQL versions | Discover/install/pin; singleton `brew services` management | Isolated instances and data directories |
| PostgreSQL versions | Discover/install/pin; singleton `brew services` management | Isolated clusters with major-version safeguards |
| Redis versions | Discover/install/pin; singleton `brew services` management | Multiple Fabric LaunchAgents and ports |
| Valkey versions | Discover/install/pin; singleton `brew services` management | Multiple Fabric LaunchAgents and ports |
| Meilisearch versions | Discover/install/pin; singleton `brew services` management | Isolated databases, keys, and ports |
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

Open `Package.swift` in Xcode, or use the command line:

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

The local bundle is ad-hoc signed. Developer ID signing, hardened runtime, and notarization are planned before distribution.

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
- No automatic `brew update`.
- No `sudo` for Homebrew operations.
- No silent third-party tap installation.
- No automatic removal of packages, pins, or service data.
- Services should bind to loopback by default in the Fabric-owned runtime.
- Database major upgrades will require explicit compatibility and backup workflows.

## Development status

Fabric is pre-release software. `0.1.0` establishes the native app, package locking, persistence, and Homebrew bridge. The detailed roadmap and managed todo list live in [`docs/MASTER_PLAN.md`](docs/MASTER_PLAN.md); architectural decisions live in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
