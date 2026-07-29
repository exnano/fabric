import Foundation

/// Coordinates persistence and the active service backend.
///
/// UI code talks only to this actor. Keeping the workflow off the main actor makes
/// long-running Homebrew operations safe for a responsive SwiftUI interface.
public actor FabricRuntime {
    private let store: any ServiceInstanceStoring
    private let backend: any ServiceManagingBackend

    public init(
        store: any ServiceInstanceStoring,
        backend: any ServiceManagingBackend
    ) {
        self.store = store
        self.backend = backend
    }

    public static func live() -> FabricRuntime {
        let paths = FabricPaths.live
        return FabricRuntime(
            store: JSONServiceInstanceStore(registryURL: paths.registry),
            backend: HomebrewClient()
        )
    }

    public func dashboard() async throws -> DashboardSnapshot {
        let instances = try await store.load()
        guard !instances.isEmpty else {
            return DashboardSnapshot(services: [])
        }

        do {
            let runtimeStates = try await backend.runtimeStates(for: instances)
            let services = instances.map { instance in
                ManagedService(
                    instance: instance,
                    runtime: runtimeStates[instance.id] ?? .offline
                )
            }
            return DashboardSnapshot(services: services)
        } catch {
            let services = instances.map { instance in
                ManagedService(
                    instance: instance,
                    runtime: ServiceRuntimeState(
                        status: .warning,
                        summary: error.localizedDescription
                    )
                )
            }
            return DashboardSnapshot(
                services: services,
                notices: [error.localizedDescription]
            )
        }
    }

    public func catalog() async throws -> CatalogSnapshot {
        try await backend.catalog()
    }

    @discardableResult
    public func addService(_ request: AddServiceRequest) async throws -> ServiceInstance {
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw FabricError.invalidServiceName
        }

        var instances = try await store.load()
        guard !instances.contains(where: {
            $0.source.identifier == request.catalogItem.source.identifier
        }) else {
            throw FabricError.duplicateService(request.catalogItem.displayName)
        }

        let packageLock = try await backend.installAndLock(request.catalogItem)
        let endpoints = request.catalogItem.kind.defaultEndpoints.map {
            ServiceEndpoint(name: $0.name, port: $0.port)
        }
        let instance = ServiceInstance(
            name: name,
            kind: request.catalogItem.kind,
            source: request.catalogItem.source,
            packageLock: packageLock,
            endpoints: endpoints
        )

        instances.append(instance)
        try await store.save(instances)
        return instance
    }

    public func perform(
        _ action: ServiceAction,
        serviceID: UUID
    ) async throws {
        let instances = try await store.load()
        guard let instance = instances.first(where: { $0.id == serviceID }) else {
            throw FabricError.serviceNotFound
        }
        try await backend.perform(action, for: instance)
    }

    @discardableResult
    public func performPackageAction(
        _ action: PackageAction,
        serviceID: UUID
    ) async throws -> ServiceInstance {
        var instances = try await store.load()
        guard let index = instances.firstIndex(where: { $0.id == serviceID }) else {
            throw FabricError.serviceNotFound
        }

        let packageLock = try await backend.performPackageAction(action, for: instances[index])
        instances[index].packageLock = packageLock
        try await store.save(instances)
        return instances[index]
    }

    public func meilisearchMasterKey(serviceID: UUID) async throws -> String? {
        let instance = try await serviceInstance(serviceID: serviceID)
        return try await backend.meilisearchMasterKey(for: instance)
    }

    public func setMeilisearchMasterKey(
        _ masterKey: String,
        serviceID: UUID
    ) async throws {
        let instance = try await serviceInstance(serviceID: serviceID)
        try await backend.setMeilisearchMasterKey(masterKey, for: instance)
    }

    public func upgradeMeilisearchDatabase(serviceID: UUID) async throws {
        let instance = try await serviceInstance(serviceID: serviceID)
        try await backend.upgradeMeilisearchDatabase(for: instance)
    }

    public func logFiles(serviceID: UUID) async throws -> [LogFileReference] {
        let instance = try await serviceInstance(serviceID: serviceID)
        return try await backend.logFiles(for: instance)
    }

    private func serviceInstance(serviceID: UUID) async throws -> ServiceInstance {
        let instances = try await store.load()
        guard let instance = instances.first(where: { $0.id == serviceID }) else {
            throw FabricError.serviceNotFound
        }
        return instance
    }
}
