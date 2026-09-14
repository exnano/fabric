@testable import FabricCore
import Foundation
import Testing

struct HomebrewDashboardTests {
    @Test("Dashboard overlays external upgrades and unpins without saving the registry")
    func metadataOverlay() async throws {
        let instances = [instance("vendor/tools/meilisearch"), instance("redis")]
        let info = #"{"formulae":[{"name":"meilisearch","full_name":"vendor/tools/meilisearch","linked_keg":"1.10.0","installed":[{"version":"1.9.0"},{"version":"1.11.0"},{"version":"1.10.0"}],"pinned":false},{"name":"redis","full_name":"redis","linked_keg":null,"installed":[{"version":"9.0"},{"version":"10.0"},{"version":"8.0"}],"pinned":true}]}"#
        let runner = DashboardRunner(info: info)
        let store = DashboardStore(instances)
        let runtime = FabricRuntime(store: store, backend: client(runner))
        let snapshot = try await runtime.dashboard()
        #expect(snapshot.services.map(\.instance.versionLabel) == ["1.10.0", "10.0"])
        #expect(snapshot.services.map { $0.instance.packageLock?.isPinned } == [false, true])
        #expect(snapshot.services.allSatisfy { $0.runtime.status == .running })
        #expect(snapshot.services[0].instance.packageLock?.lockedAt == instances[0].packageLock?.lockedAt)
        #expect(snapshot.services[0].instance.packageLock?.pinOwnership == .fabric)
        #expect(snapshot.services[0].instance.packageLock?.kegPath == nil)
        #expect(snapshot.notices.isEmpty)
        #expect(await store.load() == instances)
        #expect(await store.saves == 0)
        let requests = await runner.requests
        #expect(requests.map(\.arguments) == [
            ["info", "--json=v2", "--formula", "redis", "vendor/tools/meilisearch"],
            ["services", "list", "--json"],
        ])
        #expect(requests.allSatisfy { $0.environment["HOMEBREW_NO_AUTO_UPDATE"] == "1" })
    }

    @Test("Metadata failures preserve the observed running status and saved metadata", arguments: [
        "command failure", "invalid json", #"{"formulae":[]}"#,
        #"{"formulae":[{"name":"meilisearch","full_name":"other/tools/meilisearch","installed":[{"version":"2"}],"pinned":false}]}"#,
        #"{"formulae":[{"name":"meilisearch","full_name":"vendor/tools/meilisearch","installed":[],"pinned":false}]}"#,
    ])
    func metadataFailure(info: String) async throws {
        let original = instance("vendor/tools/meilisearch")
        let store = DashboardStore([original])
        let snapshot = try await FabricRuntime(store: store, backend: client(DashboardRunner(info: info))).dashboard()
        #expect(snapshot.services.first?.instance == original)
        #expect(snapshot.services.first?.runtime.status == .running)
        #expect(snapshot.notices.count == 1)
        #expect(!snapshot.notices.joined().contains("secret"))
        #expect(await store.saves == 0)
    }

    @Test("Status query failures never expose command output in warning summaries")
    func statusFailure() async throws {
        let store = DashboardStore([instance("redis")])
        let runner = DashboardRunner(info: "invalid json", services: "command failure")
        let snapshot = try await FabricRuntime(store: store, backend: client(runner)).dashboard()
        #expect(snapshot.services.first?.runtime.status == .warning)
        #expect(snapshot.notices.count == 2)
        #expect(!snapshot.services.map(\.runtime.summary).joined().contains("secret"))
        #expect(!snapshot.notices.joined().contains("secret"))
        #expect(await store.saves == 0)
    }

    @Test("Empty and Valet-only metadata requests do not invoke Homebrew")
    func nonHomebrewMetadata() async throws {
        let runner = DashboardRunner(info: "")
        let backend = client(runner)
        let empty = try await backend.packageMetadata(for: [])
        let valet = ServiceInstance(name: "Valet", kind: .laravelValet, source: .laravelValet(executablePath: "/unused/valet"), packageLock: nil, endpoints: [])
        let metadata = try await backend.packageMetadata(for: [valet])
        #expect(empty.isEmpty)
        #expect(metadata.isEmpty)
        #expect(await runner.requests.isEmpty)
    }

    @Test("Formula matching is tap-aware and ambiguous short names are rejected")
    func formulaMatching() throws {
        let data = Data(#"{"formulae":[{"name":"redis","full_name":"a/b/redis","linked_keg":"99","installed":[{"version":"9"},{"version":"10"}],"pinned":false},{"name":"redis","full_name":"c/d/redis","installed":[{"version":"3"}],"pinned":true}]}"#.utf8)
        let records = try JSONDecoder().decode(HomebrewInfo.self, from: data).formulae
        #expect(HomebrewFormulaInfo.match("redis", in: records) == nil)
        #expect(HomebrewFormulaInfo.match("a/b/redis", in: records)?.currentVersion == "10")
        #expect(HomebrewFormulaInfo.match("x/y/redis", in: records) == nil)
        let core = HomebrewFormulaInfo(name: "redis", fullName: "redis", linkedKeg: nil, installed: [.init(version: "7")], pinned: false)
        #expect(HomebrewFormulaInfo.match("homebrew/core/redis", in: [core])?.currentVersion == "7")
    }

    @Test("Warnings classify recent evidence without displaying logs or keys", arguments: [
        ("Database version 1.0 is incompatible with this Meilisearch version", "database version may be incompatible"),
        ("bind: Address already in use", "address or port"),
        ("Permission denied", "lack permission"),
        ("No space left on device", "disk space"),
        ("database already locked by another process", "service lock"),
        ("invalid configuration", "configuration may be invalid"),
    ])
    func warningClues(log: String, expected: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plist = try writeLogs(directory, text: "\(log) secret-master-key=do-not-display\n")
        let runner = DashboardRunner(info: "", services: try serviceJSON(status: "error", exit: 1, file: plist.path))
        let service = instance("vendor/tools/meilisearch")
        let states = try await client(runner).runtimeStates(for: [service])
        let state = try #require(states[service.id])
        #expect(state.status == .warning)
        #expect(state.summary.contains(expected))
        #expect(state.summary.contains("may be stale"))
        #expect(state.summary.contains("Exit code: 1"))
        #expect(state.summary.contains("LaunchAgent file is present"))
        #expect(!state.summary.contains("secret-master-key"))
        #expect(!state.summary.contains("do-not-display"))
        #expect(await runner.requests.count == 1)
    }

    @Test("Old, out-of-bounds, missing and unrelated logs do not invent a cause", arguments: ["old", "bytes", "lines", "unknown", "missing"])
    func ignoredEvidence(mode: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var text = "Address already in use\n"
        if mode == "bytes" { text += String(repeating: "x", count: 20_000) }
        if mode == "lines" { text += String(repeating: "healthy\n", count: 81) }
        if mode == "unknown" { text = "secret-master-key=do-not-display\n" }
        let plist = try writeLogs(directory, text: text)
        let log = directory.appendingPathComponent("service.log")
        if mode == "old" {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-172_800)], ofItemAtPath: log.path)
        }
        if mode == "missing" { try FileManager.default.removeItem(at: log) }
        let state = HomebrewWarningSummary.runtimeState(
            from: .init(name: "meilisearch", status: "error", user: nil, file: plist.path, exitCode: 1), kind: .meilisearch
        )
        #expect(state.status == .warning)
        #expect(!state.summary.contains("Recent log clue"))
        #expect(!state.summary.contains("secret"))
    }

    @Test("Status and exit code control warnings; unknown status payloads are not echoed")
    func statuses() {
        for (status, exit, expected) in [("started", 0, ServiceStatus.running), ("started", 2, .warning), ("stopped", 0, .offline), ("none", 0, .offline), ("stopped", 2, .warning), ("error", 0, .warning), ("secret-key", 1, .warning)] {
            let state = HomebrewWarningSummary.runtimeState(from: .init(name: "redis", status: status, user: nil, file: nil, exitCode: exit), kind: .redis)
            #expect(state.status == expected)
            #expect(!state.summary.contains("secret-key"))
        }
        #expect(HomebrewWarningSummary.explanation(for: "database version incompatible", kind: .redis) == nil)
        #expect(HomebrewWarningSummary.explanation(for: "database opened successfully", kind: .meilisearch) == nil)
    }

    private func client(_ runner: DashboardRunner) -> HomebrewClient {
        HomebrewClient(runner: runner, locator: HomebrewLocator(customPath: URL(fileURLWithPath: "/usr/bin/true")))
    }

    private func instance(_ formula: String) -> ServiceInstance {
        ServiceInstance(name: formula, kind: formula == "redis" ? .redis : .meilisearch, source: .homebrew(formula: formula), packageLock: PackageLock(formula: formula, installedVersion: "1.0", kegPath: "/old/1.0", pinOwnership: .fabric), endpoints: [])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeLogs(_ directory: URL, text: String) throws -> URL {
        let log = directory.appendingPathComponent("service.log")
        try Data(text.utf8).write(to: log)
        let plist = directory.appendingPathComponent("service.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: ["StandardErrorPath": log.path], format: .xml, options: 0)
        try data.write(to: plist)
        return plist
    }

    private func serviceJSON(status: String, exit: Int, file: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [["name": "meilisearch", "status": status, "exit_code": exit, "file": file]])
        return String(decoding: data, as: UTF8.self)
    }
}

private actor DashboardRunner: ProcessRunning {
    let info: String
    let services: String
    var requests: [ProcessRequest] = []

    init(info: String, services: String = #"[{"name":"meilisearch","status":"started","exit_code":0},{"name":"redis","status":"started","exit_code":0}]"#) {
        self.info = info
        self.services = services
    }

    func run(_ request: ProcessRequest) -> ProcessResult {
        requests.append(request)
        if request.arguments.first == "info" {
            return ProcessResult(exitCode: info == "command failure" ? 1 : 0, standardOutput: info, standardError: "secret error payload")
        }
        return ProcessResult(exitCode: services == "command failure" ? 1 : 0, standardOutput: services, standardError: "secret status payload")
    }
}

private actor DashboardStore: ServiceInstanceStoring {
    var instances: [ServiceInstance]
    var saves = 0
    init(_ instances: [ServiceInstance]) { self.instances = instances }
    func load() -> [ServiceInstance] { instances }
    func save(_ instances: [ServiceInstance]) { saves += 1; self.instances = instances }
}
