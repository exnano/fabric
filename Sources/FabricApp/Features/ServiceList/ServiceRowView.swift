import AppKit
import FabricCore
import SwiftUI

struct ServiceRowView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isUpgradeConfirmationPresented = false
    @State private var isDatabaseUpgradeConfirmationPresented = false
    @State private var isMasterKeyPresented = false
    @State private var isStatusPresented = false
    let service: ManagedService

    private var isBusy: Bool {
        model.busyServiceIDs.contains(service.id)
    }

    var body: some View {
        HStack(spacing: 16) {
            serviceIcon
            serviceIdentity

            Button {
                isStatusPresented = true
            } label: {
                StatusBadge(status: service.runtime.status)
            }
            .buttonStyle(.plain)
            .help("Show service status details")
            .accessibilityLabel("\(service.instance.name): \(service.runtime.status.displayName). Show details")
            .popover(isPresented: $isStatusPresented, arrowEdge: .bottom) {
                ServiceStatusDetails(service: service) {
                    isStatusPresented = false
                    model.showLogs(for: service)
                }
            }
            .frame(width: 104, alignment: .leading)

            actionControls
                .frame(width: 132, alignment: .trailing)

            if service.instance.packageLock != nil {
                packageMenu
            }

            Button {
                model.showLogs(for: service)
            } label: {
                Label("Logs", systemImage: "doc.text.magnifyingglass")
                    .frame(minWidth: 64)
            }
            .help("Open service logs")
        }
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .help(service.runtime.summary)
        .sheet(isPresented: $isMasterKeyPresented) {
            MeilisearchMasterKeySheet(service: service)
                .environmentObject(model)
        }
        .confirmationDialog(
            "Upgrade \(service.instance.name)?",
            isPresented: $isUpgradeConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Upgrade \(service.instance.packageLock?.formula ?? service.instance.name)") {
                model.performPackageAction(.upgrade, on: service)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Homebrew may restart this service. Unversioned database formulae can cross major versions; back up important data first.")
        }
        .confirmationDialog(
            "Upgrade the Meilisearch database?",
            isPresented: $isDatabaseUpgradeConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Backup Verified — Restart with --upgrade-db", role: .destructive) {
                model.upgradeMeilisearchDatabase(on: service)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only continue after a snapshot task has succeeded and you have verified the backup. This stops Meilisearch and launches the installed binary with --upgrade-db; it does not install a new version. Requires flag support (v1.51+). Databases older than v1.12 require a dump migration. Upgrades are not atomic and can corrupt data on failure. Launch acceptance does not mean the upgrade task succeeded.")
        }
    }

    private var serviceIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.quaternary)
            Image(systemName: service.instance.kind.symbolName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 52, height: 52)
    }

    private var serviceIdentity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(service.instance.name)
                    .font(.headline)

                Text(service.instance.versionLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)

            if !service.instance.endpoints.isEmpty {
                Text(service.instance.endpoints.map(\.address).joined(separator: "  ·  "))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if service.runtime.status == .warning {
                Button {
                    isStatusPresented = true
                } label: {
                    Text(service.runtime.summary)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .help("Show the full warning and troubleshooting details")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var actionControls: some View {
        if isBusy {
            ProgressView()
                .controlSize(.small)
                .frame(width: 132, alignment: .center)
        } else {
            HStack(spacing: 6) {
                actionButton(.start, symbol: "play.fill")
                actionButton(.stop, symbol: "stop.fill")
                actionButton(.restart, symbol: "arrow.clockwise")
            }
        }
    }

    private var packageMenu: some View {
        Menu {
            if service.instance.packageLock?.isPinned == true {
                Button("Unlock Version", systemImage: "lock.open") {
                    model.performPackageAction(.unpin, on: service)
                }
            } else {
                Button("Lock Version", systemImage: "lock") {
                    model.performPackageAction(.pin, on: service)
                }
            }

            Divider()

            Button("Upgrade with Homebrew…", systemImage: "arrow.up.circle") {
                isUpgradeConfirmationPresented = true
            }

            if service.instance.kind == .meilisearch {
                Divider()

                Button("Master Key…", systemImage: "key") {
                    isMasterKeyPresented = true
                }

                Button("Upgrade Database…", systemImage: "externaldrive.badge.arrow.up") {
                    isDatabaseUpgradeConfirmationPresented = true
                }
            }
        } label: {
            Image(systemName: service.instance.packageLock?.isPinned == true ? "lock.fill" : "lock.open")
                .frame(width: 17, height: 17)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isBusy)
        .help(service.instance.packageLock?.isPinned == true ? "Version locked" : "Version unlocked")
    }

    private func actionButton(_ action: ServiceAction, symbol: String) -> some View {
        Button {
            model.perform(action, on: service)
        } label: {
            Image(systemName: symbol)
                .frame(width: 17, height: 17)
        }
        .disabled(isRedundant(action))
        .help(action.displayName)
    }

    private func isRedundant(_ action: ServiceAction) -> Bool {
        switch action {
        case .start: service.runtime.status == .running
        case .stop: service.runtime.status == .offline
        case .restart: service.runtime.status == .offline
        }
    }
}

private struct ServiceStatusDetails: View {
    let service: ManagedService
    let openLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(service.instance.name, systemImage: service.instance.kind.symbolName)
                .font(.headline)
            StatusBadge(status: service.runtime.status)
            Text(service.runtime.summary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if service.runtime.status == .warning {
                Text("An exit code indicates a failed process, not its root cause. Check the latest log timestamps before taking action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let package = service.instance.packageLock {
                Divider()
                Text("Installed: \(package.formula) \(package.installedVersion)")
                    .font(.caption.monospaced())
                Text(package.isPinned
                    ? "Locked in Homebrew. Unlock to allow brew upgrade."
                    : "Unlocked in Homebrew. Eligible for brew upgrade.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Installed package version—not a probe of the running process. A restart or database migration may still be required after an upgrade.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Open Logs", systemImage: "doc.text.magnifyingglass", action: openLogs)
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct MeilisearchMasterKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    let service: ManagedService

    @State private var masterKey = ""
    @State private var isRevealed = false
    @State private var isLoading = true
    @State private var isSaving = false

    private var isValid: Bool {
        masterKey.lengthOfBytes(using: .utf8) >= 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meilisearch Master Key")
                    .font(.title2.weight(.semibold))
                Text("The master key grants full control of this Meilisearch instance.")
                    .foregroundStyle(.secondary)
            }

            if isLoading {
                ProgressView("Reading from Keychain…")
                    .frame(maxWidth: .infinity, minHeight: 64)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Group {
                            if isRevealed {
                                TextField("At least 16 bytes", text: $masterKey)
                            } else {
                                SecureField("At least 16 bytes", text: $masterKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        Button {
                            isRevealed.toggle()
                        } label: {
                            Image(systemName: isRevealed ? "eye.slash" : "eye")
                        }
                        .help(isRevealed ? "Hide master key" : "Show master key")

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(masterKey, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .disabled(masterKey.isEmpty)
                        .help("Copy master key")
                    }

                    Text(isValid ? "Stored in macOS Keychain." : "The key must contain at least 16 bytes.")
                        .font(.caption)
                        .foregroundStyle(isValid ? Color.secondary : Color.red)
                }

                HStack {
                    Button("Generate Secure Key") {
                        masterKey = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                        isRevealed = true
                    }

                    Spacer()

                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }

                    Button("Save & Restart") {
                        isSaving = true
                        Task {
                            if await model.setMeilisearchMasterKey(masterKey, on: service) {
                                dismiss()
                            } else {
                                isSaving = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid || isSaving)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .task {
            masterKey = await model.meilisearchMasterKey(for: service) ?? ""
            isLoading = false
        }
    }
}

private struct StatusBadge: View {
    let status: ServiceStatus

    private var color: Color {
        switch status {
        case .running: .green
        case .warning: .orange
        case .offline: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(status.displayName)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }
}
