import FabricCore
import SwiftUI

struct ServiceRowView: View {
    @EnvironmentObject private var model: AppModel
    let service: ManagedService

    private var isBusy: Bool {
        model.busyServiceIDs.contains(service.id)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
                Image(systemName: service.instance.kind.symbolName)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(service.instance.name)
                        .font(.headline)
                    StatusBadge(status: service.runtime.status)
                }

                HStack(spacing: 6) {
                    Text(service.instance.kind.displayName)
                    Text("·")
                    Text(service.instance.source.subtitle)
                    Text("·")
                    Text(service.instance.versionLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if !service.instance.endpoints.isEmpty {
                    Text(service.instance.endpoints.map(\.address).joined(separator: "  ·  "))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 22)
            }

            Button {
                model.showLogs(for: service)
            } label: {
                Label("Logs", systemImage: "doc.text.magnifyingglass")
            }
            .help("Open service logs")

            HStack(spacing: 6) {
                actionButton(.start, symbol: "play.fill")
                actionButton(.stop, symbol: "stop.fill")
                actionButton(.restart, symbol: "arrow.clockwise")
            }
        }
        .padding(.vertical, 2)
        .help(service.runtime.summary)
    }

    private func actionButton(_ action: ServiceAction, symbol: String) -> some View {
        Button {
            model.perform(action, on: service)
        } label: {
            Image(systemName: symbol)
                .frame(width: 17, height: 17)
        }
        .disabled(isBusy || isRedundant(action))
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
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(status.displayName)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}
