import Foundation

/// Centralized filesystem locations prevent service adapters from inventing their own
/// paths and make future backup/export behavior predictable.
public struct FabricPaths: Hashable, Sendable {
    public let applicationSupport: URL
    public let instances: URL
    public let logs: URL
    public let registry: URL

    public init(applicationSupport: URL, logs: URL) {
        self.applicationSupport = applicationSupport
        self.instances = applicationSupport.appendingPathComponent("Instances", isDirectory: true)
        self.logs = logs
        self.registry = applicationSupport.appendingPathComponent("services.json")
    }

    public static var live: FabricPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return FabricPaths(
            applicationSupport: home
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent("Exnano Fabric", isDirectory: true),
            logs: home
                .appendingPathComponent("Library/Logs", isDirectory: true)
                .appendingPathComponent("Exnano Fabric", isDirectory: true)
        )
    }

    public func instanceDirectory(for id: UUID) -> URL {
        instances.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    public func logDirectory(for id: UUID) -> URL {
        logs.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }
}
