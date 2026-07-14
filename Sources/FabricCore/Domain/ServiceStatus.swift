import Foundation

/// The three health states shown throughout Fabric.
public enum ServiceStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case offline
    case running
    case warning

    public var displayName: String {
        switch self {
        case .offline: "Offline"
        case .running: "Running"
        case .warning: "Warning"
        }
    }

    /// Running services sort first, then services needing attention, then offline ones.
    public var sortPriority: Int {
        switch self {
        case .running: 0
        case .warning: 1
        case .offline: 2
        }
    }
}

public enum ServiceSort: String, CaseIterable, Codable, Identifiable, Sendable {
    case name
    case status

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .name: "Name"
        case .status: "Status"
        }
    }
}
