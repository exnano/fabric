import FabricCore
import SwiftUI

struct AddServiceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    @State private var selectedItemID: String?
    @State private var serviceName = ""
    @State private var searchText = ""

    private var filteredItems: [ServiceCatalogItem] {
        guard !searchText.isEmpty else { return model.catalogItems }
        return model.catalogItems.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.kind.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.source.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedItem: ServiceCatalogItem? {
        model.catalogItems.first { $0.id == selectedItemID }
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if model.isLoadingCatalog, model.catalogItems.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Reading Homebrew catalog…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No Matching Services",
                        systemImage: "magnifyingglass",
                        description: Text("Refresh the catalog or try another search.")
                    )
                } else {
                    List(filteredItems, selection: $selectedItemID) { item in
                        CatalogRow(item: item)
                            .tag(item.id)
                    }
                    .listStyle(.sidebar)
                }
            }
            .navigationTitle("Add Service")
            .frame(minWidth: 320, idealWidth: 340, maxWidth: 420)
            .navigationSplitViewColumnWidth(min: 320, ideal: 340, max: 420)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search services")
        } detail: {
            if let item = selectedItem {
                serviceDetails(item)
            } else {
                ContentUnavailableView(
                    "Choose a Service",
                    systemImage: "plus.circle",
                    description: Text("Select a version or detected integration from the catalog.")
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .frame(width: 1_080, height: 560)
        .onChange(of: selectedItemID) { _, _ in
            if let item = selectedItem {
                serviceName = item.displayName
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.loadCatalog() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoadingCatalog || model.isAddingService)

            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .disabled(model.isAddingService)
            .keyboardShortcut(.cancelAction)

            Spacer()

            if let item = selectedItem {
                Button(item.isInstalled ? "Add Service" : "Install & Add") {
                    Task {
                        await model.addService(item: item, name: serviceName)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.isAddingService
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func serviceDetails(_ item: ServiceCatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: item.kind.symbolName)
                    .font(.system(size: 28))
                    .frame(width: 48, height: 48)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.title2.weight(.semibold))
                    Text(item.source.subtitle)
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                TextField("Instance name", text: $serviceName)

                LabeledContent("Version", value: item.versionLabel)
                LabeledContent("Source", value: item.trust.displayName)
                LabeledContent("Installed", value: item.isInstalled ? "Yes" : "No")
                LabeledContent("Pinned", value: item.isPinned ? "Yes" : "Fabric will pin it")

                if !item.kind.defaultEndpoints.isEmpty {
                    LabeledContent("Default endpoints") {
                        Text(
                            item.kind.defaultEndpoints
                                .map { "\($0.name) :\($0.port)" }
                                .joined(separator: ", ")
                        )
                    }
                }
            }
            .formStyle(.grouped)

            Label {
                Text("Version 0.1 uses Homebrew's singleton service definition. True isolated instances with automatic free-port allocation are tracked for the next runtime phase.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            Spacer()
        }
        .padding(24)
        .overlay {
            if model.isAddingService {
                ZStack {
                    Rectangle().fill(.background.opacity(0.82))
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(item.isInstalled ? "Registering service…" : "Installing and pinning with Homebrew…")
                            .font(.headline)
                        Text("This can take several minutes. Fabric will not run brew update.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct CatalogRow: View {
    let item: ServiceCatalogItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.symbolName)
                .frame(width: 24)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(item.versionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.isInstalled {
                Image(systemName: item.isPinned ? "lock.fill" : "checkmark.circle.fill")
                    .foregroundStyle(item.isPinned ? .orange : .green)
                    .help(item.isPinned ? "Pinned" : "Installed")
            }
        }
        .padding(.vertical, 4)
    }
}
