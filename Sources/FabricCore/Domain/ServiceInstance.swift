import Foundation

/// Identifies where a manageable service comes from.
public enum ServiceSource: Codable, Hashable, Sendable {
    case homebrew(formula: String)
    case laravelValet(executablePath: String)

    public var identifier: String {
        switch self {
        case let .homebrew(formula): "homebrew:\(formula)"
        case let .laravelValet(path): "valet:\(path)"
        }
    }

    public var subtitle: String {
        switch self {
        case let .homebrew(formula): formula
        case .laravelValet: "Composer global installation"
        }
    }

    public var formula: String? {
        guard case let .homebrew(formula) = self else { return nil }
        return formula
    }
}

/// Records who owned a Homebrew pin before Fabric registered the package.
/// Fabric must never remove a pin that was already owned by the user.
public enum PinOwnership: String, Codable, Hashable, Sendable {
    case preexisting
    case fabric
}

/// A durable record of the exact package version selected for an instance.
public struct PackageLock: Codable, Hashable, Sendable {
    public let formula: String
    public let installedVersion: String
    public let kegPath: String?
    public let pinOwnership: PinOwnership
    public let isPinned: Bool
    public let lockedAt: Date

    public init(
        formula: String,
        installedVersion: String,
        kegPath: String?,
        pinOwnership: PinOwnership,
        isPinned: Bool = true,
        lockedAt: Date = .now
    ) {
        self.formula = formula
        self.installedVersion = installedVersion
        self.kegPath = kegPath
        self.pinOwnership = pinOwnership
        self.isPinned = isPinned
        self.lockedAt = lockedAt
    }

    private enum CodingKeys: String, CodingKey {
        case formula
        case installedVersion
        case kegPath
        case pinOwnership
        case isPinned
        case lockedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formula = try container.decode(String.self, forKey: .formula)
        installedVersion = try container.decode(String.self, forKey: .installedVersion)
        kegPath = try container.decodeIfPresent(String.self, forKey: .kegPath)
        pinOwnership = try container.decode(PinOwnership.self, forKey: .pinOwnership)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? true
        lockedAt = try container.decode(Date.self, forKey: .lockedAt)
    }
}

/// A named endpoint lets one service expose more than one port (for example,
/// Mailpit's SMTP and web ports) without making the port the instance identity.
public struct ServiceEndpoint: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var host: String
    public var port: Int

    public init(
        id: UUID = UUID(),
        name: String,
        host: String = "127.0.0.1",
        port: Int
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
    }

    public var address: String { "\(host):\(port)" }
}

/// User-configured service registration persisted by Fabric.
public struct ServiceInstance: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let kind: ServiceKind
    public let source: ServiceSource
    public var packageLock: PackageLock?
    public var endpoints: [ServiceEndpoint]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        kind: ServiceKind,
        source: ServiceSource,
        packageLock: PackageLock?,
        endpoints: [ServiceEndpoint],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.source = source
        self.packageLock = packageLock
        self.endpoints = endpoints
        self.createdAt = createdAt
    }

    public var versionLabel: String {
        packageLock?.installedVersion ?? "Detected"
    }
}

/// Runtime information is refreshed from the operating system and is not persisted.
public struct ServiceRuntimeState: Codable, Hashable, Sendable {
    public let status: ServiceStatus
    public let summary: String
    public let checkedAt: Date

    public init(
        status: ServiceStatus,
        summary: String,
        checkedAt: Date = .now
    ) {
        self.status = status
        self.summary = summary
        self.checkedAt = checkedAt
    }

    public static let offline = ServiceRuntimeState(
        status: .offline,
        summary: "The service is not running."
    )
}

public struct ManagedService: Identifiable, Hashable, Sendable {
    public let instance: ServiceInstance
    public let runtime: ServiceRuntimeState

    public init(instance: ServiceInstance, runtime: ServiceRuntimeState) {
        self.instance = instance
        self.runtime = runtime
    }

    public var id: UUID { instance.id }
}

public enum PackageAction: String, CaseIterable, Codable, Hashable, Sendable {
    case pin
    case unpin
    case upgrade

    public var displayName: String {
        switch self {
        case .pin: "Lock Version"
        case .unpin: "Unlock Version"
        case .upgrade: "Upgrade"
        }
    }
}

public enum ServiceAction: String, CaseIterable, Codable, Hashable, Sendable {
    case start
    case stop
    case restart

    public var displayName: String {
        rawValue.capitalized
    }
}
