import Foundation

/// Log text is evidence only: all displayed explanations come from fixed strings.
enum HomebrewWarningSummary {
    static func runtimeState(from record: HomebrewServiceRecord?, kind: ServiceKind) -> ServiceRuntimeState {
        guard let record else { return .offline }
        let status = record.status.lowercased()
        let failed = record.exitCode.map { $0 != 0 } ?? false
        if status == "started", !failed {
            return ServiceRuntimeState(status: .running, summary: "Managed by Homebrew services.")
        }
        if ["none", "stopped"].contains(status), !failed { return .offline }

        let knownStatuses = ["started", "stopped", "none", "error", "unknown", "scheduled", "other"]
        let statusLabel = knownStatuses.contains(status) ? status : "an unrecognized status"
        var summary = "Homebrew reports \(statusLabel)."
        if let exitCode = record.exitCode { summary += " Exit code: \(exitCode)." }
        summary += failed
            ? " The service process exited unsuccessfully."
            : " The service is not confirmed running."
        if let path = record.file, !path.isEmpty {
            // Do not echo arbitrary paths or payloads from external metadata.
            summary += FileManager.default.fileExists(atPath: path)
                ? " LaunchAgent file is present."
                : " LaunchAgent file is missing."
        }
        if let clue = recentLogClue(plistPath: record.file, kind: kind) {
            summary += " Recent log clue (may be stale): \(clue)"
        }
        summary += " Open Logs for details."
        return ServiceRuntimeState(status: .warning, summary: summary)
    }

    private static func recentLogClue(plistPath: String?, kind: ServiceKind) -> String? {
        guard let plistPath,
              let data = boundedRegularFile(URL(fileURLWithPath: plistPath), limit: 64 * 1024, tail: false),
              let paths = try? PropertyListDecoder().decode(LaunchAgentLogPaths.self, from: data) else {
            return nil
        }
        for path in [paths.standardErrorPath, paths.standardOutPath].compactMap({ $0 }) {
            let url = URL(fileURLWithPath: path)
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  Date().timeIntervalSince(modified) >= -60,
                  Date().timeIntervalSince(modified) <= 24 * 60 * 60,
                  let data = boundedRegularFile(url, limit: 16 * 1024, tail: true) else { continue }
            let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).suffix(80)
            for line in lines.reversed() {
                if let clue = explanation(for: String(line).lowercased(), kind: kind) { return clue }
            }
        }
        return nil
    }

    private static func boundedRegularFile(_ url: URL, limit: Int, tail: Bool) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd()
            if !tail, size > UInt64(limit) { return nil }
            let offset = tail && size > UInt64(limit) ? size - UInt64(limit) : 0
            try handle.seek(toOffset: offset)
            var data = try handle.read(upToCount: limit) ?? Data()
            // Ignore the partial first line when the bounded tail starts mid-file.
            if offset > 0 {
                guard let newline = data.firstIndex(of: 10) else { return nil }
                data = Data(data[data.index(after: newline)...])
            }
            return data
        } catch {
            return nil
        }
    }

    static func explanation(for line: String, kind: ServiceKind) -> String? {
        if kind == .meilisearch,
           line.contains("database"),
           (line.contains("incompatible") || line.contains("not compatible")),
           line.contains("version") {
            return "The Meilisearch database version may be incompatible with the installed binary. Review database upgrade requirements before retrying."
        }
        if line.contains("address already in use") || line.contains("eaddrinuse") {
            return "Another process may already be using the service address or port."
        }
        if line.contains("permission denied") || line.contains("operation not permitted") {
            return "The service may lack permission to access a required resource."
        }
        if line.contains("no space left on device") {
            return "The service may have run out of disk space."
        }
        if line.contains("lock"),
           line.contains("another process") || line.contains("already locked") {
            return "Another process may hold the database or service lock."
        }
        if line.contains("invalid configuration") || (line.contains("configuration file") && line.contains("parse error")) {
            return "The service configuration may be invalid."
        }
        return nil
    }
}
