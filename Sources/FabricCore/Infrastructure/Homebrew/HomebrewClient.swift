import Foundation

/// Homebrew-backed service management used by Fabric's first release.
///
/// Homebrew remains the package owner. This bridge intentionally supports one
/// registered instance per formula because `brew services` has one launchd label per
/// formula. Fabric-owned, multi-instance LaunchAgents are the next runtime phase.
public actor HomebrewClient: ServiceManagingBackend {
    private let runner: any ProcessRunning
    private let locator: HomebrewLocator
    private let homeDirectory: URL
    private let meilisearchMasterKeys: any MeilisearchMasterKeyStoring
    private var busyMeilisearchFormulae: Set<String> = []

    public init(
        runner: any ProcessRunning = FoundationProcessRunner(),
        locator: HomebrewLocator = HomebrewLocator(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        meilisearchMasterKeys: any MeilisearchMasterKeyStoring = KeychainMeilisearchMasterKeyStore()
    ) {
        self.runner = runner
        self.locator = locator
        self.homeDirectory = homeDirectory
        self.meilisearchMasterKeys = meilisearchMasterKeys
    }

    public func catalog() async throws -> CatalogSnapshot {
        let brew = try locator.locate()

        async let formulaResult = runBrew(
            brew,
            arguments: ["formulae"],
            timeout: .seconds(120)
        )
        async let installedResult = runBrew(
            brew,
            arguments: ["list", "--formula", "--versions"],
            timeout: .seconds(120)
        )
        async let pinnedResult = runBrew(
            brew,
            arguments: ["list", "--pinned"],
            timeout: .seconds(120)
        )

        let formulaOutput = try await formulaResult.standardOutput
        let installedOutput = try await installedResult.standardOutput
        let pinnedOutput = try await pinnedResult.standardOutput

        let installed = HomebrewOutputParser.installedFormulae(from: installedOutput)
        let pinned = HomebrewOutputParser.pinnedFormulae(from: pinnedOutput)
        let availableNames = Set(HomebrewOutputParser.formulaNames(from: formulaOutput))
            .union(installed.keys)

        var items = availableNames.compactMap { formula -> ServiceCatalogItem? in
            guard let kind = ServiceKind.kind(forFormula: formula) else { return nil }

            // These integrations are detected and managed only when the user already
            // owns them. Fabric does not offer to install web/PHP environment tools.
            if [.phpFPM, .nginx, .caddy].contains(kind), installed[formula] == nil {
                return nil
            }

            let installedFormula = installed[formula]
            let trust: CatalogTrust = formula.contains("/")
                ? .configuredThirdPartyTap
                : .homebrewCore

            return ServiceCatalogItem(
                kind: kind,
                displayName: catalogDisplayName(kind: kind, formula: formula),
                source: .homebrew(formula: formula),
                installedVersions: installedFormula?.versions ?? [],
                isInstalled: installedFormula != nil,
                isPinned: pinned.contains(formula),
                trust: trust
            )
        }

        if let valet = await detectValet() {
            items.append(valet)
        }

        items.sort {
            if $0.kind.displayName == $1.kind.displayName {
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            return $0.kind.displayName.localizedStandardCompare($1.kind.displayName) == .orderedAscending
        }

        return CatalogSnapshot(
            homebrewPath: brew.path,
            items: items,
            notices: [
                "Fabric never runs brew update automatically.",
                "PHP-FPM, Nginx, Caddy, and Laravel Valet are shown only when detected locally.",
            ]
        )
    }

    public func installAndLock(_ item: ServiceCatalogItem) async throws -> PackageLock? {
        guard case let .homebrew(formula) = item.source else {
            return nil
        }
        try validate(formula: formula)

        let brew = try locator.locate()
        let installedBefore = try await installedFormulae(using: brew)
        let pinnedBefore = try await pinnedFormulae(using: brew)

        if installedBefore[formula] == nil {
            _ = try await runBrew(
                brew,
                arguments: ["install", formula],
                timeout: .seconds(30 * 60)
            )
        }

        if !pinnedBefore.contains(formula) {
            _ = try await runBrew(
                brew,
                arguments: ["pin", formula],
                timeout: .seconds(120)
            )
        }

        return try await packageLock(
            formula: formula,
            pinOwnership: pinnedBefore.contains(formula) ? .preexisting : .fabric,
            using: brew
        )
    }

    public func packageMetadata(for instances: [ServiceInstance]) async throws -> [UUID: PackageLock] {
        let formulae = Set(instances.compactMap(\.source.formula)).sorted()
        guard !formulae.isEmpty else { return [:] }
        for formula in formulae { try validate(formula: formula) }
        let brew = try locator.locate()
        let result = try await runBrew(
            brew,
            arguments: ["info", "--json=v2", "--formula"] + formulae,
            timeout: .seconds(120)
        )
        let info = try JSONDecoder().decode(HomebrewInfo.self, from: Data(result.standardOutput.utf8))
        var metadata: [UUID: PackageLock] = [:]
        for instance in instances {
            guard let formula = instance.source.formula else { continue }
            guard let record = HomebrewFormulaInfo.match(formula, in: info.formulae),
                  let version = record.currentVersion else {
                throw FabricError.packageVersionMissing(formula)
            }
            let old = instance.packageLock
            // Never carry an old keg path across an external upgrade. No filesystem
            // or registry writes are needed to display these current observations.
            metadata[instance.id] = PackageLock(
                formula: formula,
                installedVersion: version,
                kegPath: old?.installedVersion == version ? old?.kegPath : nil,
                pinOwnership: old?.pinOwnership ?? .preexisting,
                isPinned: record.pinned,
                lockedAt: old?.lockedAt ?? instance.createdAt
            )
        }
        return metadata
    }

    public func runtimeStates(
        for instances: [ServiceInstance]
    ) async throws -> [UUID: ServiceRuntimeState] {
        guard !instances.isEmpty else { return [:] }

        let brew = try locator.locate()
        let records = try await serviceRecords(using: brew)
        var states: [UUID: ServiceRuntimeState] = [:]

        for instance in instances {
            switch instance.source {
            case let .homebrew(formula):
                let serviceName = shortFormulaName(formula)
                let exact = records.filter { $0.name == formula }
                let short = records.filter { $0.name == serviceName }
                let record = exact.count == 1 ? exact[0] : (short.count == 1 ? short[0] : nil)
                states[instance.id] = HomebrewWarningSummary.runtimeState(from: record, kind: instance.kind)
            case let .laravelValet(executablePath):
                states[instance.id] = await valetRuntimeState(executablePath: executablePath)
            }
        }

        return states
    }

    public func perform(
        _ action: ServiceAction,
        for instance: ServiceInstance
    ) async throws {
        let busyFormula = try beginMeilisearchMutation(instance)
        defer { if let busyFormula { busyMeilisearchFormulae.remove(busyFormula) } }
        switch instance.source {
        case let .homebrew(formula):
            try validate(formula: formula)
            let brew = try locator.locate()
            if instance.kind == .meilisearch, action != .stop {
                try await runMeilisearchService(
                    action: action,
                    instance: instance,
                    brew: brew
                )
            } else {
                _ = try await runBrew(
                    brew,
                    arguments: ["services", action.rawValue, formula],
                    timeout: .seconds(5 * 60)
                )
            }
        case let .laravelValet(executablePath):
            let executable = URL(fileURLWithPath: executablePath)
            let result = try await runner.run(
                ProcessRequest(
                    executableURL: executable,
                    arguments: [action.rawValue],
                    timeout: .seconds(5 * 60)
                )
            )
            try requireSuccess(result, command: "valet \(action.rawValue)")
        }
    }

    public func performPackageAction(
        _ action: PackageAction,
        for instance: ServiceInstance
    ) async throws -> PackageLock {
        let busyFormula = try beginMeilisearchMutation(instance)
        defer { if let busyFormula { busyMeilisearchFormulae.remove(busyFormula) } }
        guard
            case let .homebrew(formula) = instance.source,
            let existingLock = instance.packageLock
        else {
            throw FabricError.catalogItemUnavailable(instance.name)
        }

        try validate(formula: formula)
        let brew = try locator.locate()
        let pinnedBefore = try await pinnedFormulae(using: brew)
        let wasPinned = pinnedBefore.contains(formula)

        switch action {
        case .pin:
            if !wasPinned {
                _ = try await runBrew(
                    brew,
                    arguments: ["pin", formula],
                    timeout: .seconds(120)
                )
            }
        case .unpin:
            if wasPinned {
                _ = try await runBrew(
                    brew,
                    arguments: ["unpin", formula],
                    timeout: .seconds(120)
                )
            }
        case .upgrade:
            if wasPinned {
                _ = try await runBrew(
                    brew,
                    arguments: ["unpin", formula],
                    timeout: .seconds(120)
                )
            }

            do {
                _ = try await runBrew(
                    brew,
                    arguments: ["upgrade", formula],
                    timeout: .seconds(30 * 60)
                )
                if wasPinned {
                    _ = try await runBrew(
                        brew,
                        arguments: ["pin", formula],
                        timeout: .seconds(120)
                    )
                }
            } catch {
                if wasPinned {
                    _ = try? await runBrew(
                        brew,
                        arguments: ["pin", formula],
                        timeout: .seconds(120)
                    )
                }
                throw error
            }
        }

        return try await packageLock(
            formula: formula,
            pinOwnership: existingLock.pinOwnership,
            using: brew
        )
    }

    public func meilisearchMasterKey(for instance: ServiceInstance) async throws -> String? {
        try requireMeilisearch(instance)
        return try meilisearchMasterKeys.masterKey(serviceID: instance.id)
    }

    public func setMeilisearchMasterKey(
        _ masterKey: String,
        for instance: ServiceInstance
    ) async throws {
        try requireMeilisearch(instance)
        let busyFormula = try beginMeilisearchMutation(instance)
        defer { if let busyFormula { busyMeilisearchFormulae.remove(busyFormula) } }
        try meilisearchMasterKeys.setMasterKey(masterKey, serviceID: instance.id)
        let brew = try locator.locate()
        try await runMeilisearchService(
            action: .restart,
            instance: instance,
            brew: brew
        )
    }

    /// Returns when launchd accepts the request, not when the database upgrade completes.
    public func upgradeMeilisearchDatabase(for instance: ServiceInstance) async throws {
        try requireMeilisearch(instance)
        let busyFormula = try beginMeilisearchMutation(instance)
        defer { if let busyFormula { busyMeilisearchFormulae.remove(busyFormula) } }
        let formula = instance.source.formula!
        try validate(formula: formula)
        let brew = try locator.locate()
        let records: [HomebrewServiceRecord]
        do {
            records = try await serviceRecords(using: brew)
        } catch {
            throw MeilisearchUpgradeError(message: "Cannot read Homebrew service records. Check brew services list before retrying. No service was stopped.")
        }
        let exact = records.filter { $0.name == formula }
        let matches = exact.isEmpty ? records.filter { $0.name == shortFormulaName(formula) } : exact
        guard matches.count == 1 else {
            throw MeilisearchUpgradeError(message: "Cannot identify one existing Meilisearch Homebrew service. Register the normal user service first.")
        }
        let masterKey = try meilisearchMasterKeys.masterKey(serviceID: instance.id)
        try await MeilisearchDatabaseUpgrader(runner: runner, homeDirectory: homeDirectory)
            .launch(record: matches[0], masterKey: masterKey)
    }

    private func beginMeilisearchMutation(_ instance: ServiceInstance) throws -> String? {
        guard instance.kind == .meilisearch, let formula = instance.source.formula else { return nil }
        let key = shortFormulaName(formula)
        guard busyMeilisearchFormulae.insert(key).inserted else {
            throw MeilisearchUpgradeError(message: "A Meilisearch operation is already in progress. Wait for it to finish before trying again.")
        }
        return key
    }

    public func logFiles(for instance: ServiceInstance) async throws -> [LogFileReference] {
        switch instance.source {
        case let .homebrew(formula):
            return try await homebrewLogFiles(formula: formula)
        case .laravelValet:
            return valetLogFiles()
        }
    }

    private func requireMeilisearch(_ instance: ServiceInstance) throws {
        guard instance.kind == .meilisearch, instance.source.formula != nil else {
            throw FabricError.catalogItemUnavailable(instance.name)
        }
    }

    private func runMeilisearchService(
        action: ServiceAction,
        instance: ServiceInstance,
        brew: URL
    ) async throws {
        let masterKey = try meilisearchMasterKeys.masterKey(serviceID: instance.id)
        if let masterKey {
            try await setLaunchEnvironment(name: "MEILI_MASTER_KEY", value: masterKey, sensitive: true)
        }

        do {
            _ = try await runBrew(
                brew,
                arguments: ["services", action.rawValue, instance.source.formula!],
                timeout: .seconds(10 * 60)
            )
        } catch {
            await clearMeilisearchLaunchEnvironment()
            throw error
        }
        await clearMeilisearchLaunchEnvironment()
    }

    private func setLaunchEnvironment(
        name: String,
        value: String,
        sensitive: Bool
    ) async throws {
        let result = try await runner.run(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/launchctl"),
                arguments: ["setenv", name, value],
                timeout: .seconds(30),
                displayCommand: sensitive
                    ? "launchctl setenv \(name) [REDACTED]"
                    : "launchctl setenv \(name) \(value)"
            )
        )
        try requireSuccess(
            result,
            command: sensitive
                ? "launchctl setenv \(name) [REDACTED]"
                : "launchctl setenv \(name) \(value)"
        )
    }

    private func clearMeilisearchLaunchEnvironment() async {
        _ = try? await runner.run(
            ProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/launchctl"),
                arguments: ["unsetenv", "MEILI_MASTER_KEY"],
                timeout: .seconds(30)
            )
        )
    }

    private func packageLock(
        formula: String,
        pinOwnership: PinOwnership,
        using brew: URL
    ) async throws -> PackageLock {
        let installed = try await installedFormulae(using: brew)
        guard let version = installed[formula]?.versions.last else {
            throw FabricError.packageVersionMissing(formula)
        }

        let pinned = try await pinnedFormulae(using: brew)
        let cellarResult = try? await runBrew(
            brew,
            arguments: ["--cellar", formula],
            timeout: .seconds(30)
        )
        let cellarPath = cellarResult?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let possibleKegPath = cellarPath.map {
            URL(fileURLWithPath: $0).appendingPathComponent(version).path
        }
        let kegPath = possibleKegPath.flatMap {
            FileManager.default.fileExists(atPath: $0) ? $0 : nil
        }

        return PackageLock(
            formula: formula,
            installedVersion: version,
            kegPath: kegPath,
            pinOwnership: pinOwnership,
            isPinned: pinned.contains(formula)
        )
    }

    private func installedFormulae(using brew: URL) async throws -> [String: InstalledFormula] {
        let result = try await runBrew(
            brew,
            arguments: ["list", "--formula", "--versions"],
            timeout: .seconds(120)
        )
        return HomebrewOutputParser.installedFormulae(from: result.standardOutput)
    }

    private func pinnedFormulae(using brew: URL) async throws -> Set<String> {
        let result = try await runBrew(
            brew,
            arguments: ["list", "--pinned"],
            timeout: .seconds(120)
        )
        return HomebrewOutputParser.pinnedFormulae(from: result.standardOutput)
    }

    private func serviceRecords(using brew: URL) async throws -> [HomebrewServiceRecord] {
        let result = try await runBrew(
            brew,
            arguments: ["services", "list", "--json"],
            timeout: .seconds(120)
        )
        return try HomebrewOutputParser.serviceRecords(
            from: Data(result.standardOutput.utf8)
        )
    }

    private func homebrewLogFiles(formula: String) async throws -> [LogFileReference] {
        let brew = try locator.locate()
        let records = try await serviceRecords(using: brew)
        guard
            let plistPath = records.first(where: { $0.name == shortFormulaName(formula) })?.file,
            FileManager.default.fileExists(atPath: plistPath)
        else {
            return []
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: plistPath))
        let paths = try PropertyListDecoder().decode(LaunchAgentLogPaths.self, from: data)
        var references: [LogFileReference] = []

        if let standardOutPath = paths.standardOutPath {
            references.append(
                LogFileReference(label: "Standard Output", url: URL(fileURLWithPath: standardOutPath))
            )
        }
        if let standardErrorPath = paths.standardErrorPath,
           standardErrorPath != paths.standardOutPath {
            references.append(
                LogFileReference(label: "Standard Error", url: URL(fileURLWithPath: standardErrorPath))
            )
        }
        return references
    }

    private func detectValet() async -> ServiceCatalogItem? {
        let candidates = [
            homeDirectory.appendingPathComponent(".config/composer/vendor/bin/valet"),
            homeDirectory.appendingPathComponent(".composer/vendor/bin/valet"),
        ]

        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            return nil
        }

        let versionResult = try? await runner.run(
            ProcessRequest(
                executableURL: executable,
                arguments: ["--version"],
                timeout: .seconds(30)
            )
        )
        let version = versionResult?.standardOutput.isEmpty == false
            ? [versionResult!.standardOutput]
            : []

        return ServiceCatalogItem(
            kind: .laravelValet,
            displayName: "Laravel Valet",
            source: .laravelValet(executablePath: executable.path),
            installedVersions: version,
            isInstalled: true,
            isPinned: false,
            trust: .localIntegration
        )
    }

    private func valetRuntimeState(executablePath: String) async -> ServiceRuntimeState {
        do {
            let result = try await runner.run(
                ProcessRequest(
                    executableURL: URL(fileURLWithPath: executablePath),
                    arguments: ["status"],
                    timeout: .seconds(30)
                )
            )
            let combined = "\(result.standardOutput)\n\(result.standardError)".lowercased()

            if combined.contains("running") && !combined.contains("not running") {
                return ServiceRuntimeState(status: .running, summary: "Valet reports its services are running.")
            }
            if combined.contains("stopped") || combined.contains("not running") {
                return .offline
            }
            return ServiceRuntimeState(
                status: .warning,
                summary: "Valet status is unclear. Exit code: \(result.exitCode). Open Logs for details."
            )
        } catch {
            return ServiceRuntimeState(status: .warning, summary: "Valet status could not be checked. Open Logs for details.")
        }
    }

    private func valetLogFiles() -> [LogFileReference] {
        let logDirectory = homeDirectory.appendingPathComponent(".config/valet/Log", isDirectory: true)
        let candidates = [
            ("Nginx Error", "nginx-error.log"),
            ("Nginx Access", "nginx-access.log"),
            ("PHP-FPM", "php-fpm.log"),
        ]

        return candidates.compactMap { label, filename in
            let url = logDirectory.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return LogFileReference(label: label, url: url)
        }
    }

    private func runBrew(
        _ brew: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> ProcessResult {
        let result = try await runner.run(
            ProcessRequest(
                executableURL: brew,
                arguments: arguments,
                environment: ["HOMEBREW_NO_AUTO_UPDATE": "1"],
                timeout: timeout
            )
        )
        try requireSuccess(result, command: "brew \(arguments.joined(separator: " "))")
        return result
    }

    private func requireSuccess(_ result: ProcessResult, command: String) throws {
        guard result.succeeded else {
            let message = result.standardError.isEmpty
                ? result.standardOutput
                : result.standardError
            throw FabricError.commandFailed(
                command: command,
                exitCode: result.exitCode,
                message: message.isEmpty ? "No error output was provided." : message
            )
        }
    }

    private func validate(formula: String) throws {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "@+._-/")
        )
        guard
            !formula.isEmpty,
            !formula.hasPrefix("-"),
            !formula.contains(".."),
            formula.unicodeScalars.allSatisfy(allowed.contains)
        else {
            throw FabricError.invalidFormula(formula)
        }
    }

    private func shortFormulaName(_ formula: String) -> String {
        formula.split(separator: "/").last.map(String.init) ?? formula
    }

    private func catalogDisplayName(kind: ServiceKind, formula: String) -> String {
        let name = shortFormulaName(formula)
        guard let atIndex = name.lastIndex(of: "@") else {
            return kind.displayName
        }
        return "\(kind.displayName) \(name[name.index(after: atIndex)...])"
    }
}
