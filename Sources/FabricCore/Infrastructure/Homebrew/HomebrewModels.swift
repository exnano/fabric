import Foundation

struct HomebrewServiceRecord: Codable, Hashable, Sendable {
    let name: String
    let status: String
    let user: String?
    let file: String?
    let exitCode: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case user
        case file
        case exitCode = "exit_code"
    }
}

struct HomebrewInfo: Decodable {
    let formulae: [HomebrewFormulaInfo]
}

struct HomebrewFormulaInfo: Decodable {
    struct Installation: Decodable {
        let version: String
    }

    let name: String
    let fullName: String
    let linkedKeg: String?
    let installed: [Installation]
    let pinned: Bool

    enum CodingKeys: String, CodingKey {
        case name, installed, pinned
        case fullName = "full_name"
        case linkedKeg = "linked_keg"
    }

    var currentVersion: String? {
        let versions = installed.map(\.version).filter { !$0.isEmpty }
        if let linkedKeg, versions.contains(linkedKeg) { return linkedKeg }
        return versions.max { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    static func match(_ formula: String, in records: [Self]) -> Self? {
        let canonical = formula.replacingOccurrences(of: "homebrew/core/", with: "", options: .anchored)
        let exact = records.filter { $0.fullName == canonical }
        if exact.count == 1 { return exact[0] }
        // A qualified third-party formula must never resolve to another tap.
        guard !canonical.contains("/") else { return nil }
        let short = records.filter { $0.name == canonical }
        return short.count == 1 ? short[0] : nil
    }
}

struct InstalledFormula: Hashable, Sendable {
    let name: String
    let versions: [String]
}

struct LaunchAgentLogPaths: Decodable {
    let standardOutPath: String?
    let standardErrorPath: String?

    enum CodingKeys: String, CodingKey {
        case standardOutPath = "StandardOutPath"
        case standardErrorPath = "StandardErrorPath"
    }
}
