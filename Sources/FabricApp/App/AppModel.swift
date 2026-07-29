import FabricCore
import Foundation
import SwiftUI

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct LogPresentation: Identifiable {
    let service: ManagedService
    let files: [LogFileReference]

    var id: UUID { service.id }
}

/// Main-actor state observed by every Fabric scene.
/// Homebrew and persistence work remains isolated inside `FabricRuntime`.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var services: [ManagedService] = []
    @Published private(set) var catalogItems: [ServiceCatalogItem] = []
    @Published private(set) var catalogNotices: [String] = []
    @Published private(set) var dashboardNotices: [String] = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var busyServiceIDs: Set<UUID> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var isAddingService = false

    @Published var isAddServicePresented = false
    @Published var logPresentation: LogPresentation?
    @Published var alert: AppAlert?

    private let runtime: FabricRuntime
    private var monitoringTask: Task<Void, Never>?

    init(
        runtime: FabricRuntime = .live(),
        initialServices: [ManagedService] = []
    ) {
        self.runtime = runtime
        services = initialServices
    }

    /// Dashboard ordering is intentionally stable: localized service name first,
    /// then health status when two instances share the same name.
    var sortedServices: [ManagedService] {
        services.sorted { lhs, rhs in
            let nameOrder = lhs.instance.name.localizedStandardCompare(rhs.instance.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.runtime.status.sortPriority < rhs.runtime.status.sortPriority
        }
    }

    var runningCount: Int {
        services.count { $0.runtime.status == .running }
    }

    func startMonitoring() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task { [weak self] in
            guard let self else { return }
            await refresh()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { break }
                await refresh(showSpinner: false)
            }
        }
    }

    func refresh(showSpinner: Bool = true) async {
        if showSpinner { isRefreshing = true }
        defer { if showSpinner { isRefreshing = false } }

        do {
            let snapshot = try await runtime.dashboard()
            services = snapshot.services
            dashboardNotices = snapshot.notices
            lastRefresh = snapshot.refreshedAt
        } catch {
            present(error, title: "Could Not Refresh Services")
        }
    }

    func presentAddService() {
        isAddServicePresented = true
        Task { await loadCatalog() }
    }

    func loadCatalog() async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }

        do {
            let snapshot = try await runtime.catalog()
            catalogItems = snapshot.items
            catalogNotices = snapshot.notices
        } catch {
            catalogItems = []
            present(error, title: "Could Not Load Homebrew Catalog")
        }
    }

    func addService(item: ServiceCatalogItem, name: String) async {
        isAddingService = true
        defer { isAddingService = false }

        do {
            try await runtime.addService(
                AddServiceRequest(catalogItem: item, name: name)
            )
            isAddServicePresented = false
            await refresh()
        } catch {
            present(error, title: "Could Not Add Service")
        }
    }

    func perform(_ action: ServiceAction, on service: ManagedService) {
        guard !busyServiceIDs.contains(service.id) else { return }
        busyServiceIDs.insert(service.id)

        Task {
            defer { busyServiceIDs.remove(service.id) }
            do {
                try await runtime.perform(action, serviceID: service.id)
                await refresh(showSpinner: false)
            } catch {
                present(error, title: "Could Not \(action.displayName) \(service.instance.name)")
                await refresh(showSpinner: false)
            }
        }
    }

    func performPackageAction(_ action: PackageAction, on service: ManagedService) {
        guard !busyServiceIDs.contains(service.id) else { return }
        busyServiceIDs.insert(service.id)

        Task {
            defer { busyServiceIDs.remove(service.id) }
            do {
                try await runtime.performPackageAction(action, serviceID: service.id)
                await refresh(showSpinner: false)
            } catch {
                present(error, title: "Could Not \(action.displayName) \(service.instance.name)")
                await refresh(showSpinner: false)
            }
        }
    }

    func showLogs(for service: ManagedService) {
        Task {
            do {
                let files = try await runtime.logFiles(serviceID: service.id)
                guard !files.isEmpty else { throw FabricError.logUnavailable }
                logPresentation = LogPresentation(service: service, files: files)
            } catch {
                present(error, title: "Could Not Open Logs")
            }
        }
    }

    private func present(_ error: Error, title: String) {
        alert = AppAlert(title: title, message: error.localizedDescription)
    }
}
