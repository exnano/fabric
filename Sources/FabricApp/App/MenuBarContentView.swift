import AppKit
import FabricCore
import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
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

            Divider()

            if model.sortedServices.isEmpty {
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
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.sortedServices.prefix(8)) { service in
                            MenuBarServiceRow(service: service)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 300)
            }

            Divider()

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
        .frame(width: 340)
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
                .frame(width: 22)
                .foregroundStyle(service.runtime.status == .running ? .green : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(service.instance.name)
                    .lineLimit(1)
                Text(service.runtime.status.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.perform(
                    service.runtime.status == .running ? .stop : .start,
                    on: service
                )
            } label: {
                Image(systemName: service.runtime.status == .running ? "stop.fill" : "play.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(model.busyServiceIDs.contains(service.id))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }
}
