import Foundation

/// The service families Fabric knows how to discover and manage.
///
/// Formula names are intentionally matched at runtime. Homebrew adds and removes
/// versioned formulae over time, so a compiled list of exact versions would age badly.
public enum ServiceKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case mariaDB
    case mySQL
    case postgreSQL
    case redis
    case valkey
    case meilisearch
    case typesense
    case mailpit
    case rustFS
    case phpFPM
    case laravelValet
    case nginx
    case caddy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mariaDB: "MariaDB"
        case .mySQL: "MySQL"
        case .postgreSQL: "PostgreSQL"
        case .redis: "Redis"
        case .valkey: "Valkey"
        case .meilisearch: "Meilisearch"
        case .typesense: "Typesense"
        case .mailpit: "Mailpit"
        case .rustFS: "RustFS"
        case .phpFPM: "PHP-FPM"
        case .laravelValet: "Laravel Valet"
        case .nginx: "Nginx"
        case .caddy: "Caddy"
        }
    }

    /// SF Symbol name used by the macOS interface. Keeping the symbol identifier in
    /// the domain avoids duplicating service-to-icon mappings across multiple views.
    public var symbolName: String {
        switch self {
        case .mariaDB, .mySQL, .postgreSQL: "cylinder.split.1x2"
        case .redis, .valkey: "memorychip"
        case .meilisearch, .typesense: "magnifyingglass.circle"
        case .mailpit: "envelope.badge"
        case .rustFS: "externaldrive.connected.to.line.below"
        case .phpFPM: "chevron.left.forwardslash.chevron.right"
        case .laravelValet: "v.circle"
        case .nginx: "network"
        case .caddy: "shield.lefthalf.filled"
        }
    }

    /// Default loopback endpoints. These are templates, not globally reserved ports.
    /// Future Fabric-owned LaunchAgents will allocate a free port for each instance.
    public var defaultEndpoints: [EndpointTemplate] {
        switch self {
        case .mariaDB, .mySQL:
            [EndpointTemplate(name: "Database", port: 3_306)]
        case .postgreSQL:
            [EndpointTemplate(name: "Database", port: 5_432)]
        case .redis, .valkey:
            [EndpointTemplate(name: "Database", port: 6_379)]
        case .meilisearch:
            [EndpointTemplate(name: "HTTP", port: 7_700)]
        case .typesense:
            [EndpointTemplate(name: "HTTP", port: 8_108)]
        case .mailpit:
            [
                EndpointTemplate(name: "SMTP", port: 1_025),
                EndpointTemplate(name: "Web UI", port: 8_025),
            ]
        case .rustFS:
            [
                EndpointTemplate(name: "S3 API", port: 9_000),
                EndpointTemplate(name: "Console", port: 9_001),
            ]
        case .phpFPM:
            [EndpointTemplate(name: "FastCGI", port: 9_000)]
        case .laravelValet:
            []
        case .nginx:
            [EndpointTemplate(name: "HTTP", port: 8_080)]
        case .caddy:
            [
                EndpointTemplate(name: "HTTP", port: 80),
                EndpointTemplate(name: "HTTPS", port: 443),
            ]
        }
    }

    /// Returns true when a formula name belongs to this service family.
    /// The final path component is used so tapped formulae such as `owner/tap/name`
    /// can be discovered without silently installing or trusting a new tap.
    public func matches(formula: String) -> Bool {
        let name = formula.split(separator: "/").last.map(String.init) ?? formula

        switch self {
        case .mariaDB:
            return name == "mariadb" || name.hasPrefix("mariadb@")
        case .mySQL:
            return name == "mysql" || name.hasPrefix("mysql@")
        case .postgreSQL:
            return name == "postgresql" || name.hasPrefix("postgresql@")
        case .redis:
            return name == "redis" || name.hasPrefix("redis@")
        case .valkey:
            return name == "valkey" || name.hasPrefix("valkey@")
        case .meilisearch:
            return name == "meilisearch" || name.hasPrefix("meilisearch@")
        case .typesense:
            return name.localizedCaseInsensitiveContains("typesense")
        case .mailpit:
            return name == "mailpit" || name.hasPrefix("mailpit@")
        case .rustFS:
            return name.localizedCaseInsensitiveContains("rustfs")
        case .phpFPM:
            return name == "php" || name.hasPrefix("php@")
        case .laravelValet:
            return false
        case .nginx:
            return name == "nginx" || name.hasPrefix("nginx@")
        case .caddy:
            return name == "caddy" || name.hasPrefix("caddy@")
        }
    }

    public static func kind(forFormula formula: String) -> ServiceKind? {
        allCases.first { $0.matches(formula: formula) }
    }
}

public struct EndpointTemplate: Codable, Hashable, Sendable {
    public let name: String
    public let port: Int

    public init(name: String, port: Int) {
        self.name = name
        self.port = port
    }
}
