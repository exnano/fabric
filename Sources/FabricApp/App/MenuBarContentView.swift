import AppKit
import FabricCore
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel

    private var serviceListHeight: CGFloat {
        let visibleRows = min(model.sortedServices.count, 5)
        return CGFloat(visibleRows) * 54
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            serviceContent
            Divider()
            footer
        }
        .frame(width: 430)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Fabric")
                    .font(.headline)
                Text("\(model.runningCount) of \(model.services.count) services running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
            .help("Refresh service status")
        }
        .padding(12)
    }

    @ViewBuilder
    private var serviceContent: some View {
        if model.services.isEmpty {
            menuEmptyState
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Services")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(model.services.count.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.sortedServices) { service in
                            MenuBarServiceRow(service: service)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                // MenuBarExtra does not infer a ScrollView's intrinsic height. An
                // explicit viewport prevents a non-empty service list collapsing.
                .frame(height: serviceListHeight)
            }
        }
    }

    private var menuEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No services added")
                .font(.subheadline.weight(.medium))
            Text("Open Fabric to add a Homebrew service.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
    }

    private var footer: some View {
        HStack {
            Button("Open Fabric") {
                openManagementWindow()
            }
            .keyboardShortcut("o")

            Spacer()

            Button("Quit Fabric") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
    }

    private func openManagementWindow() {
        // Close the transient menu-bar panel before transferring focus to the main
        // window. The short yield lets SwiftUI create a previously closed window.
        dismiss()
        openWindow(id: "management")

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            DockPresenceController.focusManagementWindow()
        }
    }
}

private struct MenuBarServiceRow: View {
    @EnvironmentObject private var model: AppModel
    let service: ManagedService

    private var isBusy: Bool {
        model.busyServiceIDs.contains(service.id)
    }

    private var statusColor: Color {
        switch service.runtime.status {
        case .running: .green
        case .warning: .orange
        case .offline: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: service.instance.kind.symbolName)
                .frame(width: 24)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.instance.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(service.instance.endpoints.map(\.address).joined(separator: " · "))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(service.runtime.status.displayName)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(statusColor)
            .frame(width: 66, alignment: .leading)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 94)
            } else {
                HStack(spacing: 4) {
                    actionButton(.start, symbol: "play.fill")
                    actionButton(.stop, symbol: "stop.fill")
                    actionButton(.restart, symbol: "arrow.clockwise")
                }
                .frame(width: 94, alignment: .trailing)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 54)
    }

    private func actionButton(_ action: ServiceAction, symbol: String) -> some View {
        Button {
            model.perform(action, on: service)
        } label: {
            Image(systemName: symbol)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .disabled(isRedundant(action))
        .help("\(action.displayName) \(service.instance.name)")
    }

    private func isRedundant(_ action: ServiceAction) -> Bool {
        switch action {
        case .start: service.runtime.status == .running
        case .stop: service.runtime.status == .offline
        case .restart: service.runtime.status == .offline
        }
    }
}
