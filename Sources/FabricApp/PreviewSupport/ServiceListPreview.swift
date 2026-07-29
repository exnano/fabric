#if DEBUG
import FabricCore
import SwiftUI

private actor PreviewServiceBackend: ServiceManagingBackend {
    func catalog() async throws -> CatalogSnapshot {
        CatalogSnapshot(homebrewPath: nil, items: [])
    }

    func installAndLock(_ item: ServiceCatalogItem) async throws -> PackageLock? {
        nil
    }

    func runtimeStates(
        for instances: [ServiceInstance]
    ) async throws -> [UUID: ServiceRuntimeState] {
        [:]
    }

    func perform(_ action: ServiceAction, for instance: ServiceInstance) async throws {}

    func logFiles(for instance: ServiceInstance) async throws -> [LogFileReference] {
        []
    }
}

@MainActor
private enum ServiceListPreviewData {
    static let services: [ManagedService] = [
        service(
            name: "PostgreSQL",
            kind: .postgreSQL,
            formula: "postgresql@17",
            version: "17.5",
            port: 5_432,
            status: .running
        ),
        service(
            name: "Redis",
            kind: .redis,
            formula: "redis",
            version: "8.2.1",
            port: 6_379,
            status: .offline
        ),
        service(
            name: "Mailpit",
            kind: .mailpit,
            formula: "mailpit",
            version: "1.27.8",
            port: 8_025,
            status: .warning
        ),
    ]

    static let model = AppModel(
        runtime: FabricRuntime(
            store: InMemoryServiceInstanceStore(),
            backend: PreviewServiceBackend()
        ),
        initialServices: services
    )

    private static func service(
        name: String,
        kind: ServiceKind,
        formula: String,
        version: String,
        port: Int,
        status: ServiceStatus
    ) -> ManagedService {
        ManagedService(
            instance: ServiceInstance(
                name: name,
                kind: kind,
                source: .homebrew(formula: formula),
                packageLock: PackageLock(
                    formula: formula,
                    installedVersion: version,
                    kegPath: nil,
                    pinOwnership: .fabric
                ),
                endpoints: [ServiceEndpoint(name: "Local", port: port)]
            ),
            runtime: ServiceRuntimeState(
                status: status,
                summary: "Preview service state"
            )
        )
    }
}

#Preview("Management Window") {
    ServiceListView()
        .environmentObject(ServiceListPreviewData.model)
        .frame(width: 940, height: 640)
}
#endif
