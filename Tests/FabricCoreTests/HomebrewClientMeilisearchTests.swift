@testable import FabricCore
import Foundation
import Testing

struct HomebrewClientMeilisearchTests {
    @Test("Migration preserves the user job, privately overlays credentials, and removes temporary files", arguments: [true, false])
    func migration(loaded: Bool) async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let runner = MigrationRunner(file: fixture.plist, printCode: loaded ? 0 : 113)
        try await fixture.client(runner: runner).upgradeMeilisearchDatabase(for: fixture.instance)
        let requests = await runner.requests
        #expect(requests.map { $0.arguments.first! } == (loaded
            ? ["services", "--help", "print", "bootout", "bootstrap"]
            : ["services", "--help", "print", "bootstrap"]))
        #expect(requests[1].executableURL.path == "/usr/bin/true")
        #expect(requests.allSatisfy { !$0.arguments.joined().contains("fabric-secret") && $0.environment["MEILI_MASTER_KEY"] == nil && $0.environment["MEILI_UPGRADE_DB"] == nil })
        #expect(requests.allSatisfy { !$0.displayCommand.contains("fabric-secret") })
        let captured = try #require(await runner.captured)
        let plist = try #require(PropertyListSerialization.propertyList(from: captured, format: nil) as? [String: Any])
        var expected = fixture.contents
        expected["ProgramArguments"] = ["/usr/bin/true", "--db-path", "data/custom.ms", "--http-addr", "127.0.0.1:8800", "--upgrade-db"]
        expected["EnvironmentVariables"] = ["MEILI_MASTER_KEY": "fabric-secret", "OTHER": "keep"]
        expected["RunAtLoad"] = true
        #expect(fixture.contents["RunAtLoad"] as? Bool == false)
        #expect(plist["RunAtLoad"] as? Bool == true)
        #expect(NSDictionary(dictionary: plist).isEqual(to: expected))
        #expect(await runner.fileMode == 0o600)
        #expect(await runner.directoryMode == 0o700)
        let temporaryPath = try #require(await runner.temporaryPath)
        #expect(!FileManager.default.fileExists(atPath: temporaryPath))
        #expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: temporaryPath).deletingLastPathComponent().path))
        #expect(try Data(contentsOf: fixture.plist) == fixture.original)
    }

    @Test("No Fabric key preserves configured credentials; equals and environment database paths work", arguments: [Database.equals, .environment, .relativeEnvironment])
    fileprivate func configuredKey(database: Database) async throws {
        let fixture = try MigrationFixture(database: database)
        defer { fixture.remove() }
        let runner = MigrationRunner(file: fixture.plist)
        try await fixture.client(runner: runner, key: nil).upgradeMeilisearchDatabase(for: fixture.instance)
        let data = try #require(await runner.captured)
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect((plist["EnvironmentVariables"] as? [String: String])?["MEILI_MASTER_KEY"] == "configured-secret")
        #expect(try Data(contentsOf: fixture.plist) == fixture.original)
    }

    @Test("Unsupported or lookalike flags fail before any stop", arguments: ["--experimental-upgrade-database", "--experimental-dumpless-upgrade", "--upgrade-db-extra", "description mentions --upgrade-db", ""])
    func unsupported(help: String) async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let runner = MigrationRunner(file: fixture.plist, help: help)
        do {
            try await fixture.client(runner: runner).upgradeMeilisearchDatabase(for: fixture.instance)
            Issue.record("Expected unsupported failure")
        } catch {
            #expect(error.localizedDescription.contains("v1.51+"))
        }
        #expect(await runner.requests.map { $0.arguments.first! } == ["services", "--help"])
    }

    @Test("Unsafe database configurations fail without service mutations", arguments: [Database.missing, .relativeWithoutDirectory, .empty])
    fileprivate func unsafeDatabase(database: Database) async throws {
        let fixture = try MigrationFixture(database: database)
        defer { fixture.remove() }
        let runner = MigrationRunner(file: fixture.plist)
        await #expect(throws: MeilisearchUpgradeError.self) {
            try await fixture.client(runner: runner).upgradeMeilisearchDatabase(for: fixture.instance)
        }
        #expect(await runner.requests.count == 1)
    }

    @Test("Missing databases and regular files fail before stopping for every explicit path form", arguments: [Database.normal, .equals, .environment, .relativeEnvironment], [true, false])
    fileprivate func databaseMustExist(database: Database, regularFile: Bool) async throws {
        let fixture = try MigrationFixture(database: database)
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.databaseDirectory)
        if regularFile { try Data("not a database directory".utf8).write(to: fixture.databaseDirectory) }
        let runner = MigrationRunner(file: fixture.plist)
        do {
            try await fixture.client(runner: runner).upgradeMeilisearchDatabase(for: fixture.instance)
            Issue.record("Expected database-directory validation failure")
        } catch {
            #expect(error.localizedDescription.contains("existing directory"))
            #expect(error.localizedDescription.contains("No service was stopped"))
        }
        #expect(await runner.requests.map(\.arguments) == [["services", "list", "--json"]])
        #expect(try Data(contentsOf: fixture.plist) == fixture.original)
        #expect(FileManager.default.fileExists(atPath: fixture.databaseDirectory.path) == regularFile)
    }

    @Test("Normal restart has no legacy database-upgrade flag or environment handling")
    func normalRestart() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let runner = MigrationRunner(file: fixture.plist)
        try await fixture.client(runner: runner, key: nil).perform(.restart, for: fixture.instance)
        #expect(await runner.requests.map(\.arguments) == [
            ["services", "restart", "meilisearch"],
            ["unsetenv", "MEILI_MASTER_KEY"],
        ])
    }

    @Test("Bootstrap failures leave service stopped, clean up, and never retry", arguments: [true, false])
    func bootstrapFailure(loaded: Bool) async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let runner = MigrationRunner(file: fixture.plist, printCode: loaded ? 0 : 113, bootstrapCode: 5)
        do {
            try await fixture.client(runner: runner).upgradeMeilisearchDatabase(for: fixture.instance)
            Issue.record("Expected bootstrap failure")
        } catch {
            #expect(error.localizedDescription.contains("service is stopped"))
            #expect(error.localizedDescription.contains("brew services start meilisearch"))
            #expect(!error.localizedDescription.contains("fabric-secret"))
        }
        let requests = await runner.requests
        #expect(requests.filter { $0.arguments.first == "bootstrap" }.count == 1)
        #expect(requests.last?.arguments.first == "bootstrap")
        let path = try #require(await runner.temporaryPath)
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(try Data(contentsOf: fixture.plist) == fixture.original)
    }

    @Test("Unknown print errors never bootout or bootstrap")
    func unknownState() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let runner = MigrationRunner(file: fixture.plist, printCode: 5)
        await #expect(throws: MeilisearchUpgradeError.self) {
            try await fixture.client(runner: runner).upgradeMeilisearchDatabase(for: fixture.instance)
        }
        #expect(await runner.requests.map { $0.arguments.first! } == ["services", "--help", "print"])
    }

    @Test("Launch errors are sanitized and never trigger recovery mutations", arguments: ["print", "bootout", "bootstrap"])
    func launchErrors(stage: String) async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let runner = MigrationRunner(file: fixture.plist, failingStage: stage)
        let client = fixture.client(runner: runner)
        do {
            try await client.upgradeMeilisearchDatabase(for: fixture.instance)
            Issue.record("Expected launch failure")
        } catch {
            #expect(!error.localizedDescription.contains("fabric-secret"))
            if stage == "bootstrap" { #expect(error.localizedDescription.contains("service is stopped")) }
        }
        #expect(await runner.requests.last?.arguments.first == stage)
        if let path = await runner.temporaryPath {
            #expect(!FileManager.default.fileExists(atPath: path))
        }
        #expect(try Data(contentsOf: fixture.plist) == fixture.original)
        // Failure must release the actor's busy guard.
        try await client.perform(.stop, for: fixture.instance)
    }

    @Test("Relative or missing installed executables fail before help and stop", arguments: ["meilisearch", "/nonexistent/fabric-test-meilisearch"])
    func invalidExecutable(executable: String) async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        var plist = fixture.contents
        plist["Program"] = executable
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: fixture.plist)
        let runner = MigrationRunner(file: fixture.plist)
        await #expect(throws: MeilisearchUpgradeError.self) {
            try await fixture.client(runner: runner).upgradeMeilisearchDatabase(for: fixture.instance)
        }
        #expect(await runner.requests.count == 1)
    }

    @Test("Actor guard prevents migration and normal mutations overlapping, then releases")
    func concurrentOperations() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let runner = MigrationRunner(file: fixture.plist, pauseHelp: true)
        let client = fixture.client(runner: runner)
        let task = Task { [instance = fixture.instance] in
                    try await client.upgradeMeilisearchDatabase(for: instance)
                }
        await runner.waitUntilPaused()
        await #expect(throws: MeilisearchUpgradeError.self) {
            try await client.upgradeMeilisearchDatabase(for: fixture.instance)
        }
        await #expect(throws: MeilisearchUpgradeError.self) {
            try await client.perform(.stop, for: fixture.instance)
        }
        await #expect(throws: MeilisearchUpgradeError.self) {
            try await client.setMeilisearchMasterKey("another-key", for: fixture.instance)
        }
        await runner.resume()
        try await task.value
        try await client.perform(.stop, for: fixture.instance)
        #expect(await runner.requests.last?.arguments == ["services", "stop", "meilisearch"])
    }
}

private enum Database: Sendable { case normal, equals, environment, relativeEnvironment, missing, relativeWithoutDirectory, empty }

private struct MigrationFixture {
    let home: URL
    let plist: URL
    let databaseDirectory: URL
    let contents: [String: Any]
    let original: Data
    let instance = ServiceInstance(name: "Meilisearch", kind: .meilisearch, source: .homebrew(formula: "meilisearch"), packageLock: nil, endpoints: [])

    init(database: Database = .normal) throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = home.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        plist = directory.appendingPathComponent("homebrew.mxcl.meilisearch.plist")
        let workingDirectory = home.appendingPathComponent("work", isDirectory: true)
        databaseDirectory = workingDirectory.appendingPathComponent("data/custom.ms", isDirectory: true)
        try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        var args = ["/usr/bin/true"]
        var env = ["MEILI_MASTER_KEY": "configured-secret", "OTHER": "keep"]
        switch database {
        case .normal, .relativeWithoutDirectory: args += ["--db-path", "data/custom.ms"]
        case .equals: args += ["--db-path=\(databaseDirectory.path)"]
        case .environment: env["MEILI_DB_PATH"] = databaseDirectory.path
        case .relativeEnvironment: env["MEILI_DB_PATH"] = "data/custom.ms"
        case .missing: break
        case .empty: args += ["--db-path="]
        }
        args += [
            "--http-addr", "127.0.0.1:8800", "--upgrade-db=false", "--upgrade-db",
            "--experimental-upgrade-database", "--experimental-upgrade-database=true",
            "--experimental-dumpless-upgrade", "--experimental-dumpless-upgrade=true",
        ]
        var value: [String: Any] = [
            "Label": "homebrew.mxcl.meilisearch", "ProgramArguments": args,
            "EnvironmentVariables": env, "StandardOutPath": "/custom/logs/output.log",
            "StandardErrorPath": "/custom/logs/error.log", "KeepAlive": true,
            "RunAtLoad": false, "WorkingDirectory": workingDirectory.path, "ThrottleInterval": 10,
        ]
        if database == .relativeWithoutDirectory { value.removeValue(forKey: "WorkingDirectory") }
        contents = value
        original = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        try original.write(to: plist)
    }

    func client(runner: any ProcessRunning, key: String? = "fabric-secret") -> HomebrewClient {
        HomebrewClient(runner: runner, locator: HomebrewLocator(customPath: URL(fileURLWithPath: "/usr/bin/true")), homeDirectory: home, meilisearchMasterKeys: StubMasterKeyStore(key: key))
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}

private struct StubMasterKeyStore: MeilisearchMasterKeyStoring {
    let key: String?
    func masterKey(serviceID: UUID) throws -> String? { key }
    func setMasterKey(_ masterKey: String?, serviceID: UUID) throws {}
}

private actor MigrationRunner: ProcessRunning {
    let file: URL
    let printCode: Int32
    let bootstrapCode: Int32
    let help: String
    let pauseHelp: Bool
    let failingStage: String?
    var requests: [ProcessRequest] = []
    var captured: Data?
    var temporaryPath: String?
    var fileMode: Int?
    var directoryMode: Int?
    var continuation: CheckedContinuation<Void, Never>?
    var waiter: CheckedContinuation<Void, Never>?

    init(file: URL, printCode: Int32 = 0, bootstrapCode: Int32 = 0, help: String = "Options:\n      --upgrade-db  Upgrade database\n", pauseHelp: Bool = false, failingStage: String? = nil) {
        self.file = file
        self.printCode = printCode
        self.bootstrapCode = bootstrapCode
        self.help = help
        self.pauseHelp = pauseHelp
        self.failingStage = failingStage
    }

    func run(_ request: ProcessRequest) async throws -> ProcessResult {
        requests.append(request)
        var output = ""
        var code: Int32 = 0
        switch request.arguments.first {
        case "services" where request.arguments == ["services", "list", "--json"]:
            let record = HomebrewServiceRecord(name: "meilisearch", status: "started", user: NSUserName(), file: file.path, exitCode: nil)
            output = String(decoding: try JSONEncoder().encode([record]), as: UTF8.self)
        case "--help":
            if pauseHelp {
                await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    waiter?.resume()
                    waiter = nil
                }
            }
            output = help
        case "print": code = printCode
        case "bootstrap":
            let path = request.arguments[2]
            temporaryPath = path
            captured = try Data(contentsOf: URL(fileURLWithPath: path))
            fileMode = (try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue
            directoryMode = (try FileManager.default.attributesOfItem(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)?.intValue
            code = bootstrapCode
        default: break
        }
        if request.arguments.first == failingStage {
            throw MeilisearchUpgradeError(message: "raw runner error fabric-secret")
        }
        return ProcessResult(exitCode: code, standardOutput: output, standardError: "fabric-secret")
    }
    func waitUntilPaused() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func resume() { continuation?.resume(); continuation = nil }
}
