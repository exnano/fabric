# Changelog

All notable changes to Exnano Fabric are documented here. The project follows Semantic Versioning.

## [Unreleased]

### Added

- List currently running services, endpoints, statuses, and Stop actions in the menu-bar dropdown.

### Changed

- Redesign the dashboard with aligned service, status, lifecycle-action, and log columns.
- Enlarge the Added and Running totals and use deterministic name/status ordering.
- Restyle the Add Service catalog after native macOS System Settings patterns.

### Fixed

- Present and activate the full management window automatically when Fabric launches.
- Show Fabric in the Dock while its management window is open and hide it after the window closes.
- Keep Add Service catalog rows clear of the footer controls.
- Keep loaded log content left-aligned and wrap long lines within the viewer.

## [0.1.0] - 2026-07-14

### Added

- Native macOS SwiftUI menu-bar utility and reopenable management window.
- Service dashboard sorted by name or status.
- Offline, Running, and Warning health states.
- Start, Stop, Restart, and log actions.
- Dynamic Homebrew catalog discovery for supported formula families and versions.
- Install-and-pin workflow with package lock ownership tracking.
- Persistent service registry under Application Support.
- Detection of installed PHP-FPM, Nginx, Caddy, and Laravel Valet integrations.
- Local `Exnano Fabric.app` bundling, version metadata, and ad-hoc signing.
- Core unit tests and phased product plan.

### Known limitations

- The `0.1.x` runtime delegates to `brew services`, which supports one service job per formula. Fabric-owned isolated multi-instance LaunchAgents and automatic free-port allocation are planned for `0.2.0`.
- Developer ID signing and notarization are not configured yet.
