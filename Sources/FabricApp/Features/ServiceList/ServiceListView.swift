import FabricCore
import SwiftUI

struct ServiceListView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var loginItem = LoginItemController()

    var body: some View {
        VStack(spacing: 0) {
            dashboardHeader
            Divider()

            if model.sortedServices.isEmpty, !model.isRefreshing {
                ContentUnavailableView {
                    Label("No Services", systemImage: "server.rack")
                } description: {
                    Text("Add a supported Homebrew service to install, pin, and manage it from Fabric.")
                } actions: {
                    Button("Add Service") {
                        model.presentAddService()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                serviceList
            }
        }
        .onAppear {
            DockPresenceController.managementWindowDidOpen()
            loginItem.refreshStatus()
        }
        .onDisappear {
            DockPresenceController.managementWindowDidClose()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                loginItemControl
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh Service Status", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)
                .help("Refresh service status now. Fabric also refreshes automatically every eight seconds.")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.presentAddService()
                } label: {
                    Label("Add Service", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $model.isAddServicePresented) {
            AddServiceView()
                .environmentObject(model)
        }
        .sheet(item: $model.logPresentation) { presentation in
            LogViewer(presentation: presentation)
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var serviceList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.sortedServices.enumerated()), id: \.element.id) { index, service in
                    ServiceRowView(service: service)

                    if index < model.sortedServices.count - 1 {
                        Divider()
                            .padding(.leading, 76)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Services")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Homebrew packages stay pinned while Fabric manages their service lifecycle.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            MetricView(value: model.services.count, label: "Added")
            MetricView(value: model.runningCount, label: "Running", color: .green)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(.bar)
    }

    private var loginItemControl: some View {
        HStack(spacing: 6) {
            Toggle(
                "Open at Login",
                isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                )
            )
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .disabled(loginItem.isUpdating)
            .help("Open Fabric automatically after you sign in to macOS")
            .accessibilityValue(loginItem.isEnabled ? "Enabled" : "Disabled")

            if loginItem.isUpdating {
                ProgressView()
                    .controlSize(.small)
            } else if loginItem.requiresApproval {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Approval required in System Settings > General > Login Items")
            } else if let errorMessage = loginItem.errorMessage {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .help(errorMessage)
            }
        }
    }
}

private struct MetricView: View {
    let value: Int
    let label: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value.formatted())
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 76, alignment: .trailing)
    }
}
