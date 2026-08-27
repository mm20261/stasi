import Foundation

enum StasiResources {
    nonisolated static let bundle = resolve(
        mainBundle: .main,
        moduleBundle: .module
    )

    nonisolated static func resolve(
        mainBundle: Bundle,
        moduleBundle: @autoclosure () -> Bundle
    ) -> Bundle {
        if let url = mainBundle.url(
            forResource: "Stasi_Stasi",
            withExtension: "bundle"
        ), let packagedBundle = Bundle(url: url) {
            return packagedBundle
        }
        return moduleBundle()
    }
}
