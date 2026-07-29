@testable import FabricCore
import Foundation
import Testing

struct FabricRuntimeTests {
    @Test("Adding a catalog item persists its package lock and endpoints")
    func addService() async throws {
        let store = InMemoryServiceInstanceStore()
        let backend = FakeServiceBackend()
        let runtime = FabricRuntime(store: store, backend: backend)
        let item = ServiceCatalogItem(
            kind: .mailpit,
            displayName: "Mailpit",
            source: .homebrew(formula: "mailpit"),
            isInstalled: false,
            isPinned: false,
            trust: .homebrewCore
        )

        let added = try await runtime.addService(
            AddServiceRequest(catalogItem: item, name: "Local Mail")
        )
        let persisted = await store.load()

        #expect(added.name == "Local Mail")
        #expect(added.packageLock?.formula == "mailpit")
        #expect(added.endpoints.map(\.port) == [1_025, 8_025])
        #expect(persisted.map(\.id) == [added.id])
    }

    @Test("Package actions update the persisted package state")
    func packageAction() async throws {
        let instance = ServiceInstance(
            name: "Redis",
            kind: .redis,
            source: .homebrew(formula: "redis"),
            packageLock: PackageLock(
                formula: "redis",
                installedVersion: "1.0.0",
                kegPath: nil,
                pinOwnership: .fabric
            ),
            endpoints: [ServiceEndpoint(name: "Database", port: 6_379)]
        )
        let store = InMemoryServiceInstanceStore(instances: [instance])
        let runtime = FabricRuntime(store: store, backend: FakeServiceBackend())

        let updated = try await runtime.performPackageAction(.unpin, serviceID: instance.id)
        let persisted = await store.load()

        #expect(updated.packageLock?.isPinned == false)
        #expect(persisted.first?.packageLock?.isPinned == false)
    }

    @Test("The Homebrew bridge rejects a duplicate formula registration")
    func duplicateService() async throws {
        let store = InMemoryServiceInstanceStore()
        let backend = FakeServiceBackend()
        let runtime = FabricRuntime(store: store, backend: backend)
        let item = ServiceCatalogItem(
            kind: .nginx,
            displayName: "Nginx",
            source: .homebrew(formula: "nginx"),
            installedVersions: ["1.29.0"],
            isInstalled: true,
            isPinned: false,
            trust: .homebrewCore
        )

        _ = try await runtime.addService(AddServiceRequest(catalogItem: item, name: "Nginx"))

        await #expect(throws: FabricError.self) {
            try await runtime.addService(AddServiceRequest(catalogItem: item, name: "Nginx Two"))
        }
    }
}

private actor FakeServiceBackend: ServiceManagingBackend {
    func catalog() -> CatalogSnapshot {
        CatalogSnapshot(homebrewPath: "/opt/homebrew/bin/brew", items: [])
    }

    func installAndLock(_ item: ServiceCatalogItem) -> PackageLock? {
        guard case let .homebrew(formula) = item.source else { return nil }
        return PackageLock(
            formula: formula,
            installedVersion: item.installedVersions.last ?? "1.0.0",
            kegPath: "/opt/homebrew/Cellar/\(formula)/1.0.0",
            pinOwnership: item.isPinned ? .preexisting : .fabric
        )
    }

    func runtimeStates(
        for instances: [ServiceInstance]
    ) -> [UUID: ServiceRuntimeState] {
        Dictionary(uniqueKeysWithValues: instances.map { ($0.id, .offline) })
    }

    func perform(_ action: ServiceAction, for instance: ServiceInstance) {}

    func performPackageAction(
        _ action: PackageAction,
        for instance: ServiceInstance
    ) -> PackageLock {
        let lock = instance.packageLock!
        return PackageLock(
            formula: lock.formula,
            installedVersion: action == .upgrade ? "2.0.0" : lock.installedVersion,
            kegPath: lock.kegPath,
            pinOwnership: lock.pinOwnership,
            isPinned: action != .unpin
        )
    }

    func meilisearchMasterKey(for instance: ServiceInstance) -> String? {
        "test-master-key-1234"
    }

    func setMeilisearchMasterKey(_ masterKey: String, for instance: ServiceInstance) {}

    func upgradeMeilisearchDatabase(for instance: ServiceInstance) {}

    func logFiles(for instance: ServiceInstance) -> [LogFileReference] {
        []
    }
}
