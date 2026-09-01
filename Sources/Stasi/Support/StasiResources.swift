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
        moduleBundle: nil
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
}
