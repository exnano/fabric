import Foundation

public struct HomebrewLocator: Sendable {
    public let candidates: [URL]

    public init(customPath: URL? = nil) {
        var paths: [URL] = []
        if let customPath {
            paths.append(customPath)
        }
        paths.append(URL(fileURLWithPath: "/opt/homebrew/bin/brew"))
        paths.append(URL(fileURLWithPath: "/usr/local/bin/brew"))
        self.candidates = paths
    }

    public func locate() throws -> URL {
        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw FabricError.homebrewNotFound
        }
        return executable
    }
}
