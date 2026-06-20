import Foundation

/// Persistent local log for diagnosing menu bar app failures outside Xcode.
struct AppLog: Sendable {
    private static let writer = AppLogWriter()
    private let category: String

    static var fileURL: URL { AppLogWriter.fileURL }
    static var directoryURL: URL { AppLogWriter.directoryURL }

    init(_ category: String) {
        self.category = category
    }

    func info(_ message: String) { Self.writer.write("INFO", category, message) }
    func warning(_ message: String) { Self.writer.write("WARN", category, message) }
    func error(_ message: String) { Self.writer.write("ERROR", category, message) }
}

private final class AppLogWriter: @unchecked Sendable {
    static let directoryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("Logs", isDirectory: true)
    static let fileURL = directoryURL.appendingPathComponent("ccMonitor-app.log")

    private static let maxFileBytes: UInt64 = 5 * 1024 * 1024
    private static let keepRotated = 2

    private let queue = DispatchQueue(label: "com.ccmonitor.applog")
    private let formatter: ISO8601DateFormatter
    private var fileHandle: FileHandle?
    private var bytesWritten: UInt64 = 0

    init() {
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try? FileManager.default.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
        openHandle()
        writeSessionHeader()
    }

    func write(_ level: String, _ category: String, _ message: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.writeLine("[\(self.formatter.string(from: Date()))] [\(level)] [\(category)] \(message)")
        }
    }

    private func openHandle() {
        let path = Self.fileURL.path
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
            bytesWritten = 0
        } else {
            let attrs = try? fm.attributesOfItem(atPath: path)
            bytesWritten = (attrs?[.size] as? UInt64) ?? 0
        }
        fileHandle = FileHandle(forWritingAtPath: path)
        _ = try? fileHandle?.seekToEnd()
    }

    private func writeSessionHeader() {
        writeLine("====== ccMonitor launched \(formatter.string(from: Date())) ======")
    }

    private func writeLine(_ line: String) {
        guard let data = "\(line)\n".data(using: .utf8) else { return }
        fileHandle?.write(data)
        bytesWritten += UInt64(data.count)
        if bytesWritten >= Self.maxFileBytes {
            rotate()
        }
    }

    private func rotate() {
        try? fileHandle?.close()
        fileHandle = nil

        let fm = FileManager.default
        try? fm.removeItem(at: Self.fileURL.appendingPathExtension("\(Self.keepRotated)"))

        var idx = Self.keepRotated
        while idx > 1 {
            let from = Self.fileURL.appendingPathExtension("\(idx - 1)")
            let to = Self.fileURL.appendingPathExtension("\(idx)")
            if fm.fileExists(atPath: from.path) {
                try? fm.removeItem(at: to)
                try? fm.moveItem(at: from, to: to)
            }
            idx -= 1
        }

        let firstRotated = Self.fileURL.appendingPathExtension("1")
        try? fm.removeItem(at: firstRotated)
        if fm.fileExists(atPath: Self.fileURL.path) {
            try? fm.moveItem(at: Self.fileURL, to: firstRotated)
        }

        openHandle()
        writeLine("====== rotated \(formatter.string(from: Date())) ======")
    }
}
