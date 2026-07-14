import Foundation

public protocol ServiceInstanceStoring: Sendable {
    func load() async throws -> [ServiceInstance]
    func save(_ instances: [ServiceInstance]) async throws
}

/// Lightweight store used by previews and unit tests.
public actor InMemoryServiceInstanceStore: ServiceInstanceStoring {
    private var instances: [ServiceInstance]

    public init(instances: [ServiceInstance] = []) {
        self.instances = instances
    }

    public func load() -> [ServiceInstance] {
        instances
    }

    public func save(_ instances: [ServiceInstance]) {
        self.instances = instances
    }
}
