import FabricCore
import SwiftUI

struct ServiceListView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var loginItem = LoginItemController()
    @State private var isRestartAllConfirmationPresented = false

    var body: some View {
        VStack(spacing: 0) {
            dashboardHeader
            Divider()

            if !model.dashboardNotices.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.dashboardNotices, id: \.self) { notice in
                        Label(notice, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }

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

            Divider()
            loginItemFooter
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
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh Service Status", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)
                .help("Refresh status, installed versions, and Homebrew locks. Fabric also refreshes automatically every eight seconds.")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isRestartAllConfirmationPresented = true
                } label: {
                    Label(
                        model.isRestartingAll ? "Restarting All Services…" : "Restart All Services",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .disabled(!model.canRestartAll)
                .help(model.isRestartingAll ? "Restarting services…" : "Restart all added services")
                .alert("Restart all \(model.services.count) services?", isPresented: $isRestartAllConfirmationPresented) {
                    Button("Cancel", role: .cancel) {}
                    Button("Restart All", role: .destructive) {
                        model.restartAllServices()
                    }
                } message: {
                    Text("This briefly interrupts active connections and also starts stopped services. Fabric will restart each added service in turn. Package versions and databases will not be upgraded.")
                }
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
                Text("Locked packages stay pinned. Unlocked packages can be upgraded with Homebrew.")
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

    private var appVersionLabel: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return "Development Build"
        }
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return "Version \(version) (\(build))"
        }
        return "Version \(version)"
    }

    private var loginItemFooter: some View {
        HStack {
            Text(appVersionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
            loginItemControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var loginItemControl: some View {
        HStack(spacing: 6) {
            Toggle(
                "Start at Login",
                isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(loginItem.isUpdating)
            .help("Start Fabric automatically after you sign in to macOS")
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

