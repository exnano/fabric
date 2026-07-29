import FabricCore
import SwiftUI

struct ServiceRowView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isUpgradeConfirmationPresented = false
    let service: ManagedService

    private var isBusy: Bool {
        model.busyServiceIDs.contains(service.id)
    }

    var body: some View {
        HStack(spacing: 16) {
            serviceIcon
            serviceIdentity

            StatusBadge(status: service.runtime.status)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
