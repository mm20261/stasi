import SwiftUI

// MARK: - RootView: Sidebar + Inhalt, Avatar oben rechts, Theme-Applikation

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(SettingsStore.self) private var settings
    @Environment(AppSelection.self) private var selection

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            VStack(spacing: 0) {
                // App-Shell-Kopfzeile (v3): Avatar rechts oben, Inhalt darunter –
                // nichts kollidiert mehr mit Screen-Topbars (z. B. Filter-Chips).
                HStack {
                    Spacer()
                    avatarButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .preferredColorScheme(.light) // v3: kein Dark Mode
        .frame(minWidth: 960, minHeight: 620)
        // v3/V4-Feature: Vier-Schritte-Onboarding bei erstem Start
        .overlay {
            if !settings.onboardingDone {
                ZStack {
                    Theme.background.opacity(0.96).ignoresSafeArea()
                    OnboardingView()
                        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
                }
                .transition(reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.panel, value: settings.onboardingDone)
        .onAppear { app.refreshPermissionState() }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    private var content: some View {
        switch selection.section {
        case .bericht: DashboardView()
        case .insights: InsightsView()
        case .protokolle: ProtocolsView()
        case .woerterbuch: DictionaryView()
        case .einstellungen: SettingsWindowView()
        case .konto: AccountView()
        }
    }

    /// Avatar-Kreis (Bild oder Initiale auf dunklem Ink), Klick → Konto
    private var avatarButton: some View {
        Button {
            selection.section = .konto
        } label: {
            Group {
                if let img = settings.avatarImage {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(Theme.Palette.surface)
                        Text(initials)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.sub)
                    }
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline))
        }
        .buttonStyle(.plain)
        .help(L10n.text("account.title"))
        .accessibilityLabel(L10n.text("account.openAccessibility"))
    }

    private var initials: String {
        let parts = settings.userName.split(separator: " ")
        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
        }
        return settings.userName.prefix(2).uppercased().isEmpty ? "S" : String(settings.userName.prefix(2)).uppercased()
    }
}
