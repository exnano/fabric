import Foundation

struct MeilisearchUpgradeError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

/// Registers a one-off job; acceptance by launchd is not database-upgrade completion.
struct MeilisearchDatabaseUpgrader: Sendable {
    let runner: any ProcessRunning
    let homeDirectory: URL

    func launch(record: HomebrewServiceRecord, masterKey: String?) async throws {
        let fm = FileManager.default
        guard let path = record.file, path.hasPrefix("/"),
              URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent()
                == homeDirectory.appendingPathComponent("Library/LaunchAgents").standardizedFileURL else {
            throw failure("Cannot locate the existing user Homebrew LaunchAgent. Register the normal service with Homebrew first.")
        }
        var plist: [String: Any]
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let decoded = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw failure("Invalid LaunchAgent.")
            }
            plist = decoded
        } catch {
            throw failure("Cannot read the existing Homebrew LaunchAgent plist. Repair its configuration before upgrading.")
        }
        guard let label = plist["Label"] as? String, !label.isEmpty, !label.contains("/"),
              var arguments = plist["ProgramArguments"] as? [String], !arguments.isEmpty,
              !arguments.contains("--") else {
            throw failure("The LaunchAgent must have a valid Label and unambiguous ProgramArguments.")
        }
        let executable = (plist["Program"] as? String) ?? arguments[0]
        guard executable.hasPrefix("/"), fm.isExecutableFile(atPath: executable) else {
            throw failure("The installed LaunchAgent executable must be an absolute, executable path. Repair the Homebrew service first.")
        }
        guard plist["EnvironmentVariables"] == nil || plist["EnvironmentVariables"] is [String: String] else {
            throw failure("The LaunchAgent environment is invalid. Repair it before upgrading.")
        }
        var environment = plist["EnvironmentVariables"] as? [String: String] ?? [:]
        var databasePaths: [String] = []
        for index in arguments.indices.dropFirst() {
            let argument = arguments[index]
            if argument == "--db-path" {
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                    throw failure("The LaunchAgent --db-path is missing its value.")
                }
                databasePaths.append(arguments[index + 1])
            } else if argument.hasPrefix("--db-path=") {
                databasePaths.append(String(argument.dropFirst("--db-path=".count)))
            }
        }
        if databasePaths.isEmpty, let path = environment["MEILI_DB_PATH"] { databasePaths.append(path) }
        guard databasePaths.count == 1, let databasePath = databasePaths.first, !databasePath.isEmpty else {
            throw failure("Configure one explicit --db-path or MEILI_DB_PATH in the existing LaunchAgent before upgrading; Fabric will not guess the database location.")
        }
        let resolvedDatabaseURL: URL
        if databasePath.hasPrefix("/") {
            resolvedDatabaseURL = URL(fileURLWithPath: databasePath)
        } else {
            guard let directory = plist["WorkingDirectory"] as? String, directory.hasPrefix("/") else {
                throw failure("A relative database path requires an absolute WorkingDirectory in the LaunchAgent. Fabric will not guess the database location.")
            }
            // Keep argv intact and validate against the same directory launchd uses.
            resolvedDatabaseURL = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(databasePath)
        }
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: resolvedDatabaseURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw failure("The configured database path must resolve to an existing directory. Check --db-path or MEILI_DB_PATH and WorkingDirectory in the LaunchAgent; Fabric will not create a fresh database for migration. No service was stopped.")
        }
        let help = try await run(executable: executable, arguments: ["--help"], message: "Cannot check the installed Meilisearch executable's --help; no service was stopped.")
        let supportsUpgrade = help.standardOutput.range(
            of: #"(?m)^\s*--upgrade-db(?=\s|=|$)"#, options: .regularExpression
        ) != nil
        guard help.exitCode == 0, !help.outputWasTruncated, supportsUpgrade else {
            throw failure("The installed Meilisearch executable does not advertise exact --upgrade-db support (v1.51+). Older versions use an experimental option, which Fabric will not substitute. Install a supported version and confirm a snapshot backup first; databases older than v1.12 require a dump-based migration. No service was stopped.")
        }
        arguments = arguments.filter {
            $0 != "--upgrade-db" && !$0.hasPrefix("--upgrade-db=")
                && $0 != "--experimental-upgrade-database" && !$0.hasPrefix("--experimental-upgrade-database=")
                && $0 != "--experimental-dumpless-upgrade" && !$0.hasPrefix("--experimental-dumpless-upgrade=")
        }
        arguments.append("--upgrade-db")
        plist["ProgramArguments"] = arguments
        plist["RunAtLoad"] = true
        if let masterKey { environment["MEILI_MASTER_KEY"] = masterKey }
        if !environment.isEmpty { plist["EnvironmentVariables"] = environment }

        let directory = fm.temporaryDirectory.appendingPathComponent("fabric-meilisearch-upgrade-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: directory) }
        let temporaryPlist = directory.appendingPathComponent("service.plist")
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            guard fm.createFile(atPath: temporaryPlist.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw failure("Cannot create private plist.")
            }
        } catch {
            throw failure("Cannot create the private migration LaunchAgent. No service was stopped.")
        }
        let domain = "gui/\(getuid())"
        let target = "\(domain)/\(label)"
        let status = try await run(arguments: ["print", target], message: "Cannot determine whether the LaunchAgent is loaded. No service was stopped.")
        guard status.exitCode == 0 || status.exitCode == 113 else {
            throw failure("Cannot determine whether the LaunchAgent is loaded (launchctl exit \(status.exitCode)). No service was stopped.")
        }
        if status.exitCode == 0 {
            let result = try await run(arguments: ["bootout", target], message: "Could not unload the LaunchAgent. Check its state manually before retrying.")
            guard result.exitCode == 0 else {
                throw failure("Could not unload the LaunchAgent. Check its state manually before retrying.")
            }
        }
        let recovery = "Migration launch failed; the service is stopped. Restart the normal service manually with Homebrew (brew services start meilisearch) after inspecting its logs and database state. Fabric did not roll back or retry migration."
        let result = try await run(arguments: ["bootstrap", domain, temporaryPlist.path], message: recovery)
        guard result.exitCode == 0 else { throw failure(recovery) }
        // launchd retains the loaded configuration; never persist migration flags in LaunchAgents.
    }

    private func run(executable: String = "/bin/launchctl", arguments: [String], message: String) async throws -> ProcessResult {
        do {
            return try await runner.run(ProcessRequest(
                executableURL: URL(fileURLWithPath: executable), arguments: arguments,
                timeout: .seconds(30), displayCommand: "Meilisearch migration preflight/launch"
            ))
        } catch {
            // Runner errors and launchctl output may echo the service's credentials.
            throw failure(message)
        }
    }

    private func failure(_ message: String) -> MeilisearchUpgradeError {
        MeilisearchUpgradeError(message: message)
    }
}
