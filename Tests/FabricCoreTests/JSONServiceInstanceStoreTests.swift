@testable import FabricCore
import Foundation
import Testing

struct JSONServiceInstanceStoreTests {
    @Test("Registry round-trips through the schema envelope")
    func roundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fabric-store-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = JSONServiceInstanceStore(
            registryURL: directory.appendingPathComponent("services.json")
        )
        let instance = ServiceInstance(
            name: "Mailpit Dev",
            kind: .mailpit,
            source: .homebrew(formula: "mailpit"),
            packageLock: PackageLock(
                formula: "mailpit",
                installedVersion: "1.30.4",
                kegPath: "/opt/homebrew/Cellar/mailpit/1.30.4",
                pinOwnership: .fabric
            ),
            endpoints: [
                ServiceEndpoint(name: "SMTP", port: 1_025),
                ServiceEndpoint(name: "Web UI", port: 8_025),
            ]
        )

        try await store.save([instance])
        let restored = try await store.load()

        #expect(restored.count == 1)
        #expect(restored[0].id == instance.id)
        #expect(restored[0].name == "Mailpit Dev")
        #expect(restored[0].packageLock?.installedVersion == "1.30.4")
        #expect(restored[0].endpoints.map(\.port) == [1_025, 8_025])
    }
}
