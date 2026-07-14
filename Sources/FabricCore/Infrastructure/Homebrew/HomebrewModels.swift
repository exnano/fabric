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
