import SwiftUI

// MARK: - RootView: Sidebar + Inhalt, Avatar oben rechts, Theme-Applikation

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(SettingsStore.self) private var settings
    @Environment(AppSelection.self) private var selection

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            Rectangle()
                .fill(Theme.Palette.line)
                .frame(width: Theme.Metrics.hairline)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.Palette.background)
        .preferredColorScheme(colorScheme)
        .overlay(alignment: .topTrailing) { avatarButton.padding(14) }
        .onAppear { app.refreshPermissionState() }
    }

    @ViewBuilder
    private var content: some View {
        switch selection.section {
        case .bericht: DashboardView()
        case .protokolle: ProtocolsView()
        case .woerterbuch: DictionaryView()
        case .einstellungen: SettingsWindowView()
        case .konto: AccountView()
        }
    }

    /// Avatar-Kreis (Bild oder Initiale), Klick → Konto
    private var avatarButton: some View {
        Button {
            selection.section = .konto
        } label: {
            Group {
                if let img = settings.avatarImage {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(Theme.tint(Theme.accent))
                        Text(initials)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent.brightenedForDarkMode())
                    }
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline))
        }
        .buttonStyle(.plain)
        .help("Konto")
    }

    private var initials: String {
        let parts = settings.userName.split(separator: " ")
        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
        }
        return settings.userName.prefix(2).uppercased().isEmpty ? "S" : String(settings.userName.prefix(2)).uppercased()
    }

    private var colorScheme: ColorScheme? {
        switch settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
