import Darwin
import Foundation

/// Executes a child process without involving a shell.
///
/// Temporary files are used for stdout and stderr instead of pipes. A child process
/// can fill a pipe buffer while the parent is waiting and deadlock; files remain safe
/// even when Homebrew produces a large amount of build output.
public struct FoundationProcessRunner: ProcessRunning, Sendable {
    public init() {}

    public func run(_ request: ProcessRequest) async throws -> ProcessResult {
        let task = Task.detached(priority: .utility) {
            try Self.execute(request)
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func execute(_ request: ProcessRequest) throws -> ProcessResult {
        guard request.executableURL.path.hasPrefix("/") else {
            throw ProcessRunnerError.executableMustBeAbsolute(request.executableURL.path)
        }

        guard FileManager.default.isExecutableFile(atPath: request.executableURL.path) else {
            throw ProcessRunnerError.executableNotFound(request.executableURL.path)
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.exnano.fabric.process.\(UUID().uuidString)", isDirectory: true)
        let standardOutputURL = temporaryDirectory.appendingPathComponent("stdout")
        let standardErrorURL = temporaryDirectory.appendingPathComponent("stderr")

        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        FileManager.default.createFile(atPath: standardOutputURL.path, contents: nil)
        FileManager.default.createFile(atPath: standardErrorURL.path, contents: nil)

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let standardOutputHandle = try FileHandle(forWritingTo: standardOutputURL)
        let standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
        defer {
            try? standardOutputHandle.close()
            try? standardErrorHandle.close()
        }

        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.standardOutput = standardOutputHandle
        process.standardError = standardErrorHandle

        // GUI applications receive a much smaller environment than interactive shells.
        // Start from the current environment but make common system paths deterministic.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        request.environment.forEach { environment[$0.key] = $0.value }
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(
                command: request.displayCommand,
                reason: error.localizedDescription
            )
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: request.timeout)
        var terminationReason: ProcessRunnerError?

        while process.isRunning {
            if Task.isCancelled {
                terminationReason = .cancelled(command: request.displayCommand)
                terminate(process)
                break
            }

            if clock.now >= deadline {
                terminationReason = .timedOut(command: request.displayCommand)
                terminate(process)
                break
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        process.waitUntilExit()
        try? standardOutputHandle.synchronize()
        try? standardErrorHandle.synchronize()

        if let terminationReason {
            throw terminationReason
        }

        let output = try readText(
            from: standardOutputURL,
            maximumBytes: request.maximumOutputBytes
        )
        let error = try readText(
            from: standardErrorURL,
            maximumBytes: request.maximumOutputBytes
        )

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: output.text,
            standardError: error.text,
            outputWasTruncated: output.wasTruncated || error.wasTruncated
        )
    }

    private static func terminate(_ process: Process) {
        process.terminate()

        // Give well-behaved servers a short opportunity to handle SIGTERM before
        // forcing the command down. This runner only controls short-lived commands;
        // managed service processes will be supervised by launchd in a later phase.
        let gracefulDeadline = Date().addingTimeInterval(1)
        while process.isRunning, Date() < gracefulDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }

    private static func readText(
        from url: URL,
        maximumBytes: Int
    ) throws -> (text: String, wasTruncated: Bool) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        let wasTruncated = data.count > maximumBytes
        let boundedData = wasTruncated ? data.prefix(maximumBytes) : data[...]
        let text = String(decoding: boundedData, as: UTF8.self)
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), wasTruncated)
    }
}
