import Darwin
import Foundation

public struct LogLine: Identifiable, Sendable, Equatable {
    public let id: UInt64
    public let text: String
}

/// An opaque position in one file snapshot. Can be passed to another reader.
public struct LogFileCursor: Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let snapshotEnd: UInt64
    public let position: UInt64
    fileprivate let endsInFragment: Bool
}

public struct LogFilePage: Sendable {
    public let lines: [LogLine]
    public let olderCursor: LogFileCursor?
    public let bytesRead: Int
    public let snapshotEnd: UInt64
}

public enum LogFileReaderError: Error, Sendable, Equatable {
    case notRegularFile
    case fileChanged
    case ioError(Int32)
}

/// Reads backwards without retaining file contents or following a rotated file.
/// Appends are excluded from an existing snapshot. In-place edits and a truncate
/// followed by regrowth between calls cannot be detected from identity and size.
public actor LogFileReader {
    public init() {}

    /// Reads at most 16 KiB. Lines are chronological; IDs are source byte offsets.
    /// A trailing LF does not produce a phantom empty line. Oversized fragments
    /// are replaced by continuation hints, whose IDs identify fragment starts.
    /// A page can be empty with a non-nil cursor; keep paging until the cursor is nil.
    /// ANSI controls are stripped per physical line, resetting malformed state at LF.
    public func page(url: URL, before: LogFileCursor? = nil) throws -> LogFilePage {
        guard url.isFileURL else { throw LogFileReaderError.notRegularFile }
        // O_NONBLOCK prevents a FIFO from blocking before we can reject its type.
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_RDONLY | O_NONBLOCK | O_CLOEXEC) } ?? -1
        }
        guard descriptor >= 0 else {
            if before != nil && (errno == ENOENT || errno == ENOTDIR) {
                throw LogFileReaderError.fileChanged
            }
            throw LogFileReaderError.ioError(errno)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let initial = try metadata(descriptor)
        let device = UInt64(UInt32(bitPattern: initial.st_dev))
        let inode = UInt64(initial.st_ino)
        if let before, before.device != device || before.inode != inode {
            throw LogFileReaderError.fileChanged
        }
        guard initial.st_mode & S_IFMT == S_IFREG else {
            throw LogFileReaderError.notRegularFile
        }
        let snapshotEnd = before?.snapshotEnd ?? UInt64(initial.st_size)
        let end = before?.position ?? snapshotEnd
        guard initial.st_size >= 0, UInt64(initial.st_size) >= snapshotEnd else {
            throw LogFileReaderError.fileChanged
        }
        let start = end > 16_384 ? end - 16_384 : 0
        try handle.seek(toOffset: start)
        let data = try handle.read(upToCount: Int(end - start)) ?? Data()
        guard data.count == Int(end - start) else { throw LogFileReaderError.fileChanged }
        let final = try metadata(descriptor)
        var pathInfo = stat()
        let pathResult = url.withUnsafeFileSystemRepresentation { path in
            path.map { fstatat(AT_FDCWD, $0, &pathInfo, 0) } ?? -1
        }
        guard final.st_size >= 0, UInt64(final.st_size) >= snapshotEnd,
              pathResult == 0, pathInfo.st_dev == initial.st_dev,
              pathInfo.st_ino == initial.st_ino else {
            throw LogFileReaderError.fileChanged
        }

        let bytes = Array(data)
        // Discard the uncertain prefix, but leave it for the next older page.
        // With no delimiter, advance by a full chunk and suppress its payload:
        // neither UTF-8 nor an escape sequence can safely be resumed mid-stream.
        let delimiter = bytes.firstIndex(of: 10).map { $0 + 1 }
        if start > 0, delimiter == bytes.count {
            // Retry without the terminal LF. This both guarantees progress and
            // allows a line plus its preceding delimiter to fit in the next read.
            let cursor = LogFileCursor(device: device, inode: inode,
                                       snapshotEnd: snapshotEnd, position: end - 1,
                                       endsInFragment: false)
            return LogFilePage(lines: [], olderCursor: cursor,
                               bytesRead: data.count, snapshotEnd: snapshotEnd)
        }
        let aligned = start == 0 ? 0 : delimiter
        let contentStart = aligned ?? bytes.count
        let olderEnd = aligned.map { start + UInt64($0) } ?? start
        var lines: [LogLine] = []
        if aligned == nil {
            lines.append(LogLine(id: start, text: "[Long line continuation omitted]"))
        } else {
            var lineStart = contentStart
            for index in contentStart..<bytes.count where bytes[index] == 10 {
                lines.append(LogLine(id: start + UInt64(lineStart),
                                     text: LogPlainText.sanitize(Array(bytes[lineStart..<index]))))
                lineStart = index + 1
            }
            if lineStart < bytes.count {
                let text = before?.endsInFragment == true
                    ? "[Long line continuation omitted]"
                    : LogPlainText.sanitize(Array(bytes[lineStart...]))
                lines.append(LogLine(id: start + UInt64(lineStart), text: text))
            }
        }
        let cursor = olderEnd == 0 ? nil : LogFileCursor(
            device: device, inode: inode, snapshotEnd: snapshotEnd,
            position: olderEnd, endsInFragment: aligned == nil
        )
        return LogFilePage(lines: lines, olderCursor: cursor,
                           bytesRead: data.count, snapshotEnd: snapshotEnd)
    }

    private func metadata(_ descriptor: Int32) throws -> stat {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw LogFileReaderError.ioError(errno) }
        return info
    }
}

/// No terminal interpretation: preserve printable Unicode and tabs, discard
/// CSI (including SGR), OSC (including hyperlinks), and other control strings.
/// Unterminated sequences consume the remainder of the physical line. Escape
/// state is deliberately reset at LF so malformed controls cannot hide later logs.
private enum LogPlainText {
    static func sanitize(_ bytes: [UInt8]) -> String {
        let scalars = Array(String(decoding: bytes, as: UTF8.self).unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let value = scalars[index].value
            index += 1
            var control = value
            if value == 0x1B {
                guard index < scalars.count else { break }
                control = scalars[index].value
                index += 1
                if control == 0x5B { control = 0x9B }
                else if control == 0x5D { control = 0x9D }
                else if [0x50, 0x58, 0x5E, 0x5F].contains(control) { control = 0x90 }
                else {
                    // ESC intermediates followed by a final byte (e.g. charset selection).
                    while (0x20...0x2F).contains(control), index < scalars.count {
                        control = scalars[index].value
                        index += 1
                    }
                    continue
                }
            }
            if control == 0x9B {
                while index < scalars.count {
                    let next = scalars[index].value
                    index += 1
                    if (0x40...0x7E).contains(next) { break }
                }
            } else if [0x90, 0x98, 0x9D, 0x9E, 0x9F].contains(control) {
                while index < scalars.count {
                    let next = scalars[index].value
                    index += 1
                    if next == 0x9C || (control == 0x9D && next == 7) { break }
                    if next == 0x1B, index < scalars.count, scalars[index].value == 0x5C {
                        index += 1
                        break
                    }
                }
            } else if value == 9 || value == 10 || (value >= 0x20 && !(0x7F...0x9F).contains(value)) {
                output.append(Unicode.Scalar(value)!)
            }
        }
        return String(output)
    }
}
