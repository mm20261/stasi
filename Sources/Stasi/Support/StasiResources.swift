import Foundation

enum StasiResources {
    // HARTE REGEL: NIEMALS `Bundle.module` als Fallback auswerten. SwiftPMs
    // generierter Accessor bricht mit fatalError ab, wenn das Paket-Bundle
    // fehlt (kaputte/veraltete .app in Downloads) → Absturz direkt beim Start
    // (siehe Crash 01.09.2026, EXC_BREAKPOINT in FontLoader). Stattdessen
    // liefern wir dann Bundle.main zurück: Ressourcen fehlen, aber die App
    // startet und muss nie wegen eines fehlenden Skript-Schritts crashen.
    nonisolated static let bundle = resolve(
        mainBundle: .main,
        moduleBundle: developmentBundle()
    )

    nonisolated static func resolve(
        mainBundle: Bundle,
        moduleBundle: @autoclosure () -> Bundle? = nil
    ) -> Bundle {
        if let url = mainBundle.url(
            forResource: "Stasi_Stasi",
            withExtension: "bundle"
        ), let packagedBundle = Bundle(url: url) {
            return packagedBundle
        }
        return moduleBundle() ?? mainBundle
    }

    /// SwiftPM legt das Bundle bei `swift build` neben Test-/Executable-Artefakte.
    /// Dieser Dateipfad-Fallback wertet bewusst NICHT `Bundle.module` aus und kann
    /// daher im beschädigten App-Paket nie dessen fatalError auslösen.
    nonisolated private static func developmentBundle() -> Bundle? {
        guard ProcessInfo.processInfo.processName == "xctest" else { return nil }
        let candidates = CommandLine.arguments.map { URL(fileURLWithPath: $0) }
            + Bundle.allBundles.map(\.bundleURL)
        for candidate in candidates {
            var directory = candidate.hasDirectoryPath
                ? candidate
                : candidate.deletingLastPathComponent()
            for _ in 0..<6 {
                let url = directory.appendingPathComponent(
                    "Stasi_Stasi.bundle",
                    isDirectory: true
                )
                if let bundle = Bundle(url: url) { return bundle }
                directory.deleteLastPathComponent()
            }
        }
        return nil
    }
}
