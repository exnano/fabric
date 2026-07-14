import AppKit
import FabricCore
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel

    private var runningServices: [ManagedService] {
        model.sortedServices.filter { $0.runtime.status == .running }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            serviceContent
            Divider()
            footer
        }
        .frame(width: 380)
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
        .padding(14)
    }

    @ViewBuilder
    private var serviceContent: some View {
        if model.services.isEmpty {
            menuEmptyState(
                symbol: "server.rack",
                title: "No services added",
                message: "Open Fabric to add a Homebrew service."
            )
        } else if runningServices.isEmpty {
            menuEmptyState(
                symbol: "pause.circle",
                title: "No services running",
                message: "Open Fabric to start a service or inspect warnings."
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Running services")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(runningServices.count.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 5)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(runningServices.prefix(8)) { service in
                            MenuBarServiceRow(service: service)
                        }

                        if runningServices.count > 8 {
                            Text("\(runningServices.count - 8) more running in Fabric")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private func menuEmptyState(
        symbol: String,
        title: String,
        message: String
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
    }

    private var footer: some View {
        HStack {
            Button("Open Fabric") {
                openManagementWindow()
            }
            .keyboardShortcut("o")

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(10)
    }

    private func openManagementWindow() {
        openWindow(id: "management")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct MenuBarServiceRow: View {
    @EnvironmentObject private var model: AppModel
    let service: ManagedService

    var body: some View {
        HStack(spacing: 10) {
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

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text(service.runtime.status.displayName)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.green)
            .frame(width: 70, alignment: .leading)

            Button {
                model.perform(.stop, on: service)
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(model.busyServiceIDs.contains(service.id))
            .help("Stop \(service.instance.name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}
