import Foundation

/// Verwaltet ausschließlich fertig geschlossene, unvollständige WAV-Dateien.
/// Der eigene Recovery-Bereich verhindert, dass Cleanup jemals History-Audio
/// berührt. Alte Dateien werden vor jeder Registrierung alters-, anzahl- und
/// größenbegrenzt entfernt.
final class AudioRecoveryStore {
    struct Policy: Sendable {
        let maxAge: TimeInterval
        let maxFiles: Int
        let maxBytes: Int64

        static let `default` = Policy(
            maxAge: 7 * 24 * 60 * 60,
            maxFiles: 20,
            maxBytes: 500 * 1_024 * 1_024
        )
    }

    let directory: URL
    private let policy: Policy
    private let fileManager: FileManager

    init(directory: URL,
         policy: Policy = .default,
         fileManager: FileManager = .default) {
        precondition(policy.maxAge >= 0)
        precondition(policy.maxFiles > 0)
        precondition(policy.maxBytes > 0)
        self.directory = directory
        self.policy = policy
        self.fileManager = fileManager
    }

    func register(_ sourceURL: URL, now: Date = Date()) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try cleanup(now: now)

        let timestamp = Self.filenameDateFormatter.string(from: now)
        let destination = directory.appendingPathComponent(
            "Stasi-Recovery-\(timestamp)-\(UUID().uuidString).wav"
        )
        try fileManager.moveItem(at: sourceURL, to: destination)
        do {
            try cleanup(now: now, preserving: destination)
        } catch {
            // Die neu registrierte Datei bleibt der wichtigere Vertrag: Ein
            // nachgelagerter Cleanup-Fehler darf sie nicht wieder unerreichbar
            // machen. Der nächste Register-/Startup-Cleanup versucht es erneut.
            DebugLog.log("STASI-AUDIO: Recovery-Cleanup fehlgeschlagen: \(error.localizedDescription)")
        }
        return destination
    }

    func cleanup(now: Date = Date()) throws {
        try cleanup(now: now, preserving: nil)
    }

    private func cleanup(now: Date, preserving protectedURL: URL?) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]
        let candidates = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).compactMap { url -> RecoveryFile? in
            guard url.pathExtension.lowercased() == "wav" else { return nil }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { return nil }
            return RecoveryFile(
                url: url,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                bytes: Int64(values.fileSize ?? 0)
            )
        }.sorted { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt { return lhs.url.path < rhs.url.path }
            return lhs.modifiedAt < rhs.modifiedAt
        }

        var retained: [RecoveryFile] = []
        for file in candidates {
            if file.url != protectedURL,
               now.timeIntervalSince(file.modifiedAt) > policy.maxAge {
                try fileManager.removeItem(at: file.url)
            } else {
                retained.append(file)
            }
        }

        var retainedBytes = retained.reduce(Int64(0)) { $0 + $1.bytes }
        while retained.count > policy.maxFiles || retainedBytes > policy.maxBytes {
            guard let removalIndex = retained.firstIndex(where: { $0.url != protectedURL }) else {
                // Eine einzelne neu registrierte WAV bleibt erreichbar, selbst
                // wenn sie alleine das Größenbudget überschreitet.
                break
            }
            let oldest = retained.remove(at: removalIndex)
            try fileManager.removeItem(at: oldest.url)
            retainedBytes -= oldest.bytes
        }
    }

    private struct RecoveryFile {
        let url: URL
        let modifiedAt: Date
        let bytes: Int64
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
