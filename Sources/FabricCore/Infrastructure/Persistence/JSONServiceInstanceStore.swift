import Foundation

/// Persists Fabric's small service registry as a versioned JSON envelope.
/// Service data directories and logs live separately and are never removed by this store.
public actor JSONServiceInstanceStore: ServiceInstanceStoring {
    private struct Envelope: Codable, Sendable {
        let schemaVersion: Int
        let services: [ServiceInstance]
    }

    private let registryURL: URL
    private let schemaVersion: Int
    private let fileManager: FileManager

    public init(
        registryURL: URL,
        schemaVersion: Int = 1,
        fileManager: FileManager = .default
    ) {
        self.registryURL = registryURL
        self.schemaVersion = schemaVersion
        self.fileManager = fileManager
    }

    public func load() throws -> [ServiceInstance] {
        guard fileManager.fileExists(atPath: registryURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: registryURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(Envelope.self, from: data)

            guard envelope.schemaVersion <= schemaVersion else {
                throw FabricError.persistence(
                    "The registry uses schema \(envelope.schemaVersion), but this build supports schema \(schemaVersion)."
                )
            }

            // Schema 1 is the initial format. Explicit migration cases will be added
            // here before a future schema starts writing different data.
            return envelope.services
        } catch let error as FabricError {
            throw error
        } catch {
            throw FabricError.persistence(error.localizedDescription)
        }
    }

    public func save(_ instances: [ServiceInstance]) throws {
        do {
            let parent = registryURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(
                Envelope(schemaVersion: schemaVersion, services: instances)
            )

            // `.atomic` writes a temporary sibling and renames it into place, so an
            // interruption cannot leave half of a JSON document behind.
            try data.write(to: registryURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: registryURL.path
            )
        } catch {
            throw FabricError.persistence(error.localizedDescription)
        }
    }
}
