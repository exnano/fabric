import Darwin
import FabricCore
import Foundation
import Testing

struct LogFileReaderTests {
    private func withFile(_ data: Data, body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fabric-log-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("meilisearch.log")
        try data.write(to: url)
        try await body(url)
    }

    @Test func meilisearchPlainTextAndOffsets() async throws {
        let lines = [
            "2026-09-14T08:00:00Z INFO meilisearch: Starting Meilisearch v1.30.4",
            "Database path:\t/Users/dev/Library/Application Support/Fabric/検索.ms",
            "Server listening on: http://localhost:7700",
            "2026-09-14T08:00:01Z INFO actix_web: GET /health 200",
            "2026-09-14T08:00:02Z WARN index_scheduler: café 🦀"
        ]
        try await withFile(Data(lines.joined(separator: "\n").utf8)) { url in
            let page = try await LogFileReader().page(url: url)
            #expect(page.lines.map(\.text) == lines)
            var offset: UInt64 = 0
            for (line, text) in zip(page.lines, lines) {
                #expect(line.id == offset)
                offset += UInt64(text.utf8.count + 1)
            }
            #expect(page.olderCursor == nil)
            #expect(page.bytesRead == Int(page.snapshotEnd))
        }
    }

    @Test func colorsHyperlinksAndControls() async throws {
        let input = "\u{1B}[32mINFO\u{1B}[0m\t検索 café 🦀\r\n"
            + "\u{1B}]8;;https://example.com\u{1B}\\dashboard\u{1B}]8;;\u{1B}\\\n"
            + "\u{1B}]0;hidden title\u{7}ready\u{1B}[2J\u{1B}[H\u{0}\u{8}\n"
            + "\u{1B}Psecret\u{1B}\\safe\n"
            + "\u{9B}31mred\u{9B}0m\u{9D}8;;url\u{9C}link\u{9D}8;;\u{9C}\n"
            + "before\u{1B}]unterminated\nnext\u{1B}["
        try await withFile(Data(input.utf8)) { url in
            let page = try await LogFileReader().page(url: url)
            #expect(page.lines.map(\.text) == ["INFO\t検索 café 🦀", "dashboard", "ready", "safe", "redlink", "before", "next"])
            #expect(page.lines.allSatisfy { !$0.text.contains("\u{1B}") })
        }
    }

    @Test(arguments: [false, true])
    func paginationFullCoverage(trailingNewline: Bool) async throws {
        let expected = (0..<2_000).map { "\($0) INFO\t索引 café 🦀 task completed" }
        let input = expected.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        try await withFile(Data(input.utf8)) { url in
            let reader = LogFileReader()
            var page = try await reader.page(url: url)
            var all = page.lines
            var calls = 1
            while let cursor = page.olderCursor {
                let previous = cursor.position
                page = try await reader.page(url: url, before: cursor)
                #expect(page.bytesRead <= 16_384)
                #expect(page.olderCursor.map { $0.position < previous } ?? true)
                #expect(page.snapshotEnd == UInt64(input.utf8.count))
                all = page.lines + all
                calls += 1
                try #require(calls < 30)
            }
            #expect(all.map(\.text) == expected)
            #expect(Set(all.map(\.id)).count == expected.count)
            var offset: UInt64 = 0
            for (line, text) in zip(all, expected) {
                #expect(line.id == offset)
                offset += UInt64(text.utf8.count + 1)
            }
        }
    }

    @Test(arguments: [0, 1, 2, 3])
    func utf8AndEscapeAtReadBoundary(shift: Int) async throws {
        // The raw chunk starts within an emoji or adjacent escape bytes. The
        // uncertain prefix is reread on the older page, never decoded in isolation.
        let first = "start 🦀\u{1B}[31mred\u{1B}[0m"
        let suffix = "\n" + String(repeating: "x", count: 16_370 + shift) + "\n"
        try await withFile(Data((first + suffix).utf8)) { url in
            let reader = LogFileReader()
            let latest = try await reader.page(url: url)
            let cursor = try #require(latest.olderCursor)
            let older = try await reader.page(url: url, before: cursor)
            #expect((older.lines + latest.lines).map(\.text) == ["start 🦀red", String(repeating: "x", count: 16_370 + shift)])
        }
    }

    @Test(arguments: ["", "\n", "\n\n", "hello\n", "hello"])
    func emptyAndTrailingLines(input: String) async throws {
        try await withFile(Data(input.utf8)) { url in
            let page = try await LogFileReader().page(url: url)
            var expected = input.components(separatedBy: "\n")
            if input.isEmpty || input.hasSuffix("\n") { expected.removeLast() }
            #expect(page.lines.map(\.text) == expected)
            #expect(page.olderCursor == nil)
            #expect(page.bytesRead == input.utf8.count)
        }
    }

    @Test(arguments: [false, true])
    func hugeLineBoundedWithHints(terminated: Bool) async throws {
        // Oversized lines are intentionally represented by hints, not lossless
        // fragments. This also prevents emitting pieces of UTF-8 or OSC payloads.
        let input = "first\n\u{1B}]8;;" + String(repeating: "🦀", count: 20_000)
            + (terminated ? "\u{7}\nlast\n" : "")
        try await withFile(Data(input.utf8)) { url in
            let reader = LogFileReader()
            var page = try await reader.page(url: url)
            var all = page.lines
            var calls = 1
            while let cursor = page.olderCursor {
                page = try await reader.page(url: url, before: cursor)
                #expect(page.bytesRead <= 16_384)
                #expect(page.olderCursor.map { $0.position < cursor.position } ?? true)
                all = page.lines + all
                calls += 1
                try #require(calls < 15)
            }
            #expect(all.first?.text == "first")
            if terminated { #expect(all.last?.text == "last") }
            #expect(all.contains { $0.text == "[Long line continuation omitted]" })
            #expect(all.allSatisfy { !$0.text.contains("�") && !$0.text.contains("\u{1B}") })
            #expect(Set(all.map(\.id)).count == all.count)
        }
    }

    @Test func appendUsesOriginalSnapshotAndCursorIsPortable() async throws {
        let input = String(repeating: "original\n", count: 4_000)
        try await withFile(Data(input.utf8)) { url in
            let first = try await LogFileReader().page(url: url)
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("NEW DATA\n".utf8))
            try handle.close()
            var page = first
            var all = first.lines
            while let cursor = page.olderCursor {
                page = try await LogFileReader().page(url: url, before: cursor)
                #expect(page.snapshotEnd == UInt64(input.utf8.count))
                all = page.lines + all
            }
            #expect(all.count == 4_000)
            #expect(all.allSatisfy { $0.text == "original" })
            let fresh = try await LogFileReader().page(url: url)
            #expect(fresh.lines.last?.text == "NEW DATA")
        }
    }

    @Test(arguments: ["rotate", "truncate", "remove"])
    func changedFileRejected(change: String) async throws {
        try await withFile(Data(String(repeating: "log line\n", count: 4_000).utf8)) { url in
            let reader = LogFileReader()
            let first = try await reader.page(url: url)
            let cursor = try #require(first.olderCursor)
            switch change {
            case "rotate":
                try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("old"))
                try Data(repeating: 65, count: 50_000).write(to: url)
            case "truncate":
                let handle = try FileHandle(forWritingTo: url)
                try handle.truncate(atOffset: 10)
                try handle.close()
            default:
                try FileManager.default.removeItem(at: url)
            }
            await #expect(throws: LogFileReaderError.fileChanged) {
                try await reader.page(url: url, before: cursor)
            }
        }
    }

    @Test func rejectsDirectoryAndFIFO() async throws {
        try await withFile(Data()) { url in
            let reader = LogFileReader()
            await #expect(throws: LogFileReaderError.notRegularFile) {
                try await reader.page(url: url.deletingLastPathComponent())
            }
            try FileManager.default.removeItem(at: url)
            let result = url.withUnsafeFileSystemRepresentation { mkfifo($0!, 0o600) }
            try #require(result == 0)
            await #expect(throws: LogFileReaderError.notRegularFile) {
                try await reader.page(url: url)
            }
        }
    }
}
