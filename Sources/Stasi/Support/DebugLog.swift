import Foundation

// MARK: - DebugLog
// NSLog landet auf diesem System nicht zuverlässig im Unified Log (ad-hoc-
// signierte App). Deshalb zusätzlich in eine Datei schreiben:
//   ~/Library/Application Support/Stasi/debug.log

enum DebugLog {
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stasi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()
    private static let queue = DispatchQueue(label: "app.stasi.debuglog")

    static func log(_ msg: String) {
        NSLog("%@", msg)
        let line = "\(Date()) \(msg)\n"
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
