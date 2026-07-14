import FabricCore
import SwiftUI

struct ServiceListView: View {
    @EnvironmentObject private var model: AppModel

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
                List(model.sortedServices) { service in
                    ServiceRowView(service: service)
                        .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                sortControls

                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)

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

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Services")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Homebrew packages stay pinned while Fabric manages their service lifecycle.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            MetricView(value: model.services.count, label: "Added")
            MetricView(value: model.runningCount, label: "Running", color: .green)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(.bar)
    }

    private var sortControls: some View {
        HStack(spacing: 4) {
            Picker("Sort", selection: $model.sort) {
                ForEach(ServiceSort.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 100)

            Button {
                model.sortAscending.toggle()
            } label: {
                Image(systemName: model.sortAscending ? "arrow.up" : "arrow.down")
            }
            .help(model.sortAscending ? "Ascending" : "Descending")
        }
    }
}

private struct MetricView: View {
    let value: Int
    let label: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value.formatted())
                .font(.title2.weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 56, alignment: .trailing)
    }
}
