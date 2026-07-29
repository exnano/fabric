import Foundation

/// Boundary between Fabric's application workflow and the package/process backend.
/// A future Launchd backend can conform without changing the SwiftUI layer.
public protocol ServiceManagingBackend: Sendable {
    func catalog() async throws -> CatalogSnapshot
    func installAndLock(_ item: ServiceCatalogItem) async throws -> PackageLock?
    func runtimeStates(
        for instances: [ServiceInstance]
    ) async throws -> [UUID: ServiceRuntimeState]
    func perform(_ action: ServiceAction, for instance: ServiceInstance) async throws
    func performPackageAction(
        _ action: PackageAction,
        for instance: ServiceInstance
    ) async throws -> PackageLock
    func logFiles(for instance: ServiceInstance) async throws -> [LogFileReference]
}
