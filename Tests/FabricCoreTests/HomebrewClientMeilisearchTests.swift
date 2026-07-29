@testable import FabricCore
import Foundation
import Testing

struct HomebrewClientMeilisearchTests {
    @Test("Meilisearch database upgrades use transient launchd environment")
    func upgradeDatabaseEnvironment() async throws {
        let runner = RecordingProcessRunner()
        let client = HomebrewClient(
            runner: runner,
            locator: HomebrewLocator(customPath: URL(fileURLWithPath: "/usr/bin/true")),
            meilisearchMasterKeys: StubMasterKeyStore(masterKey: "secret-master-key-1234")
        )

        try await client.upgradeMeilisearchDatabase(for: meilisearchInstance)
        let requests = await runner.recordedRequests()

        #expect(requests.map(\.arguments) == [
            ["setenv", "MEILI_MASTER_KEY", "secret-master-key-1234"],
            ["setenv", "MEILI_UPGRADE_DB", "true"],
            ["services", "restart", "meilisearch"],
            ["unsetenv", "MEILI_MASTER_KEY"],
            ["unsetenv", "MEILI_UPGRADE_DB"],
        ])
        #expect(requests[0].displayCommand == "launchctl setenv MEILI_MASTER_KEY [REDACTED]")
        #expect(!requests[0].displayCommand.contains("secret-master-key-1234"))
    }

    private var meilisearchInstance: ServiceInstance {
        ServiceInstance(
            name: "Meilisearch",
            kind: .meilisearch,
            source: .homebrew(formula: "meilisearch"),
            packageLock: PackageLock(
                formula: "meilisearch",
                installedVersion: "1.51.0",
                kegPath: nil,
                pinOwnership: .fabric
            ),
            endpoints: [ServiceEndpoint(name: "HTTP", port: 7_700)]
        )
    }
}

private struct StubMasterKeyStore: MeilisearchMasterKeyStoring {
    let masterKey: String?

    func masterKey(serviceID: UUID) throws -> String? {
        masterKey
    }

    func setMasterKey(_ masterKey: String?, serviceID: UUID) throws {}
}

private actor RecordingProcessRunner: ProcessRunning {
    private var requests: [ProcessRequest] = []

    func run(_ request: ProcessRequest) -> ProcessResult {
        requests.append(request)
        return ProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }

    func recordedRequests() -> [ProcessRequest] {
        requests
    }
}
