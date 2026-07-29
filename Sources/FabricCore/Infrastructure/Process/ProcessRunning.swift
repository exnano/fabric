import Foundation

public struct ProcessRequest: Hashable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let timeout: Duration
    public let maximumOutputBytes: Int
    private let displayCommandOverride: String?

    public init(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        timeout: Duration = .seconds(60),
        maximumOutputBytes: Int = 4 * 1_024 * 1_024,
        displayCommand: String? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.timeout = timeout
        self.maximumOutputBytes = maximumOutputBytes
        displayCommandOverride = displayCommand
    }

    public var displayCommand: String {
        displayCommandOverride ?? ([executableURL.lastPathComponent] + arguments).joined(separator: " ")
    }
}

public struct ProcessResult: Hashable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let outputWasTruncated: Bool

    public init(
        exitCode: Int32,
        standardOutput: String,
        standardError: String,
        outputWasTruncated: Bool = false
    ) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.outputWasTruncated = outputWasTruncated
    }

    public var succeeded: Bool { exitCode == 0 }
}

public protocol ProcessRunning: Sendable {
    func run(_ request: ProcessRequest) async throws -> ProcessResult
}

public enum ProcessRunnerError: LocalizedError, Sendable {
    case executableMustBeAbsolute(String)
    case executableNotFound(String)
    case timedOut(command: String)
    case cancelled(command: String)
    case launchFailed(command: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .executableMustBeAbsolute(path):
            "The executable path must be absolute: \(path)"
        case let .executableNotFound(path):
            "The executable does not exist or is not executable: \(path)"
        case let .timedOut(command):
            "The command timed out: \(command)"
        case let .cancelled(command):
            "The command was cancelled: \(command)"
        case let .launchFailed(command, reason):
            "Could not launch \(command): \(reason)"
        }
    }
}
