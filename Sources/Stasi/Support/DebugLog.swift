import Foundation

// MARK: - DebugLog
// NSLog landet auf diesem System nicht zuverlässig im Unified Log (ad-hoc-
// signierte App). Deshalb zusätzlich in eine Datei schreiben:
//   ~/Library/Application Support/Stasi/debug.log

enum DebugLog {
    private static let maxBytes: UInt64 = 2 * 1024 * 1024
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stasi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()
    private static let queue = DispatchQueue(label: "app.stasi.debuglog")
    /// Millisekunden-Auflösung, damit Startlatenzen messbar sind.
    private static let timestampFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func log(_ msg: String) {
        NSLog("%@", msg)
        let line = "\(Date().formatted(timestampFormat)) \(msg)\n"
        queue.async {
            try? rotateIfNeeded(at: url, maxBytes: maxBytes)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    static func rotateIfNeeded(at url: URL, maxBytes: UInt64) throws {
        let manager = FileManager.default
        guard let size = try manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
              size.uint64Value > maxBytes else { return }
        let rotatedURL = url.appendingPathExtension("1")
        if manager.fileExists(atPath: rotatedURL.path) {
            try manager.removeItem(at: rotatedURL)
        }
        try manager.moveItem(at: url, to: rotatedURL)
    }
}
