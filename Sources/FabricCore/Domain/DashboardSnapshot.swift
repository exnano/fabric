import Foundation

public struct DashboardSnapshot: Sendable {
    public let services: [ManagedService]
    public let refreshedAt: Date
    public let notices: [String]

    public init(
        services: [ManagedService],
        refreshedAt: Date = .now,
        notices: [String] = []
    ) {
        self.services = services
        self.refreshedAt = refreshedAt
        self.notices = notices
    }
}
