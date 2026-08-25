import SwiftUI

// MARK: - Navigation

@MainActor
@Observable
final class AppSelection {
    var section: Section = .bericht
    static let shared = AppSelection()

    enum Section: String, CaseIterable, Identifiable {
        case bericht, insights, protokolle, woerterbuch, einstellungen, konto
        var id: String { rawValue }

        var label: String {
            switch self {
            case .bericht: "Der Bericht"
            case .insights: "Insights"
            case .protokolle: "Protokolle"
            case .woerterbuch: "Wörterbuch"
            case .einstellungen: "Einstellungen"
            case .konto: "Konto"
            }
        }

        var icon: String {
            switch self {
            case .bericht: "house"
            case .insights: "chart.bar"
            case .protokolle: "doc.text"
            case .woerterbuch: "text.book.closed"
            case .einstellungen: "slider.horizontal.3"
            case .konto: "person"
            }
        }
    }
}

// MARK: - Sidebar (v2: 200px, einklappbar auf 64px Icon-only)

struct SidebarView: View {
    @Environment(AppSelection.self) private var selection
    @Environment(SettingsStore.self) private var settings

    @AppStorage("stasi.sidebarCollapsed") private var collapsed = false

    /// Haupt-Navigation in v2-Reihenfolge (Einstellungen ist unten fixiert).
    private static let navSections: [AppSelection.Section] = [.bericht, .insights, .woerterbuch, .konto]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Kopf: (Traffic-Light-Platz) + Panel-Toggle
            HStack {
                Spacer()
                Button {
                    withAnimation(Theme.Motion.panel) { collapsed.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.Palette.sub)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(collapsed ? "Seitenleiste ausklappen" : "Seitenleiste einklappen")
            }
            .frame(height: 34)
            .padding(.horizontal, 10)

            // Wordmark (Balken-Logo + STASI + Tagline); Logo bleibt eingeklappt sichtbar
            HStack(spacing: 8) {
                wordmarkBars
                if !collapsed {
                    Text("STASI")
                        .font(Theme.Typo.wordmark())
                        .tracking(2.2)
                        .foregroundColor(Theme.Palette.ink)
                }
            }
            .padding(.horizontal, collapsed ? 0 : 10)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)

            if !collapsed {
                Text(Copy.tagline(settings))
                    .font(.custom("Geist", size: 11))
                    .foregroundColor(Theme.Palette.sub)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
            }

            // Navigation
            VStack(spacing: 3) {
                ForEach(Self.navSections, id: \.self) { section in
                    navRow(section)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 18)

            Spacer()

            // Einstellungen (unten fixiert)
            navRow(.einstellungen)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

            // Versionszeile
            if !collapsed {
                Text("v 0.9 · Akte 001")
                    .font(Theme.Typo.kicker(size: 9.5))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundColor(Theme.Palette.sub.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                Text("© meder.dev")
                    .font(Theme.Typo.kicker(size: 9.5))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundColor(Theme.Palette.sub.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: collapsed ? Theme.Metrics.sidebarCollapsed : Theme.Metrics.sidebarWidth)
        .animation(Theme.Motion.panel, value: collapsed)
    }

    private var wordmarkBars: some View {
        HStack(spacing: 2.5) {
            Capsule().fill(Theme.accent).frame(width: 3, height: 9)
            Capsule().fill(Theme.accent).frame(width: 3, height: 16)
            Capsule().fill(Theme.accent).frame(width: 3, height: 6)
        }
    }

    private func navRow(_ section: AppSelection.Section) -> some View {
        let active = selection.section == section
        return Button {
            selection.section = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: active ? .semibold : .regular))
                    .frame(width: 20)
                    .foregroundStyle(active ? .white : Theme.Palette.sub)
                if !collapsed {
                    Text(section.label)
                        .font(Theme.Typo.nav().weight(active ? .semibold : .regular))
                        .foregroundColor(active ? .white : Theme.Palette.sub)
                    Spacer()
                }
            }
            .frame(height: 36)
            .padding(.horizontal, collapsed ? 0 : 12)
            .frame(maxWidth: collapsed ? 40 : .infinity, alignment: collapsed ? .center : .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(active ? Theme.accent : Color.clear)
            )
            .shadow(color: active ? Theme.shadow(Theme.accent) : .clear, radius: 12, x: 0, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .slideOnHover()
    }
}
