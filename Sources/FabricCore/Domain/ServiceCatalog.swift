import Foundation

public enum CatalogTrust: String, Codable, Hashable, Sendable {
    case homebrewCore
    case configuredThirdPartyTap
    case localIntegration

    public var displayName: String {
        switch self {
        case .homebrewCore: "Homebrew Core"
        case .configuredThirdPartyTap: "Configured third-party tap"
        case .localIntegration: "Detected locally"
        }
    }
}

/// One version/source option shown by the Add Service sheet.
public struct ServiceCatalogItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: ServiceKind
    public let displayName: String
    public let source: ServiceSource
    public let installedVersions: [String]
    public let isInstalled: Bool
    public let isPinned: Bool
    public let trust: CatalogTrust

    public init(
        kind: ServiceKind,
        displayName: String,
        source: ServiceSource,
        installedVersions: [String] = [],
        isInstalled: Bool,
        isPinned: Bool,
        trust: CatalogTrust
    ) {
        self.id = source.identifier
        self.kind = kind
        self.displayName = displayName
        self.source = source
        self.installedVersions = installedVersions
        self.isInstalled = isInstalled
        self.isPinned = isPinned
        self.trust = trust
    }

    public var versionLabel: String {
        if !installedVersions.isEmpty {
            return installedVersions.joined(separator: ", ")
        }

        guard case let .homebrew(formula) = source else {
            return "Detected"
        }

        if let atIndex = formula.lastIndex(of: "@") {
            return String(formula[formula.index(after: atIndex)...])
        }

        return "Latest available"
    }
}

public struct CatalogSnapshot: Codable, Hashable, Sendable {
    public let homebrewPath: String?
    public let items: [ServiceCatalogItem]
    public let notices: [String]
    public let scannedAt: Date

    public init(
        homebrewPath: String?,
        items: [ServiceCatalogItem],
        notices: [String] = [],
        scannedAt: Date = .now
    ) {
        self.homebrewPath = homebrewPath
        self.items = items
        self.notices = notices
        self.scannedAt = scannedAt
    }
}

public struct AddServiceRequest: Hashable, Sendable {
    public let catalogItem: ServiceCatalogItem
    public let name: String

    public init(catalogItem: ServiceCatalogItem, name: String) {
        self.catalogItem = catalogItem
        self.name = name
    }
}

public struct LogFileReference: Hashable, Identifiable, Sendable {
    public let label: String
    public let url: URL

    public init(label: String, url: URL) {
        self.label = label
        self.url = url
    }

    public var id: String { url.path }
}
