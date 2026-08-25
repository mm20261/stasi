import SwiftUI

// MARK: - Navigation

@MainActor
@Observable
final class AppSelection {
    var section: Section = .bericht
    static let shared = AppSelection()

    // MARK: Suche (v4: ⌘F, Volltext über alle Protokolle)
    var searchQuery = ""
    var searchFilter: ProtocolSearchFilter = .all
    /// Inkrement, das ProtocolsView auffordert, das Suchfeld zu fokussieren.
    var searchFocusRequest = UUID()

    func beginSearchFromBericht() {
        section = .protokolle
        searchFocusRequest = UUID()
    }

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

        /// v4: Strichzeichnungs-Icons 15 px (SF Symbols, regular)
        var icon: String {
            switch self {
            case .bericht: "house"
            case .insights: "chart.xyaxis.line"
            case .protokolle: "doc.text"
            case .woerterbuch: "book"
            case .einstellungen: "slider.horizontal.3"
            case .konto: "person"
            }
        }
    }
}

// MARK: - Sidebar (v3: Akzent-Aktivzeile)

struct SidebarView: View {
    @Environment(AppSelection.self) private var selection
    @Environment(SettingsStore.self) private var settings

    @AppStorage("stasi.sidebarCollapsed") private var collapsed = false

    /// Haupt-Navigation (Einstellungen ist unten fixiert, Protokolle = Unterzeile).
    private static let navSections: [AppSelection.Section] = [.bericht, .insights, .woerterbuch, .konto]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            wordmarkRow
                .padding(.top, 22)
            tagline
            navList
                .padding(.top, 18)
            Spacer()
            settingsRow
            footer
        }
        .frame(width: collapsed ? Theme.Metrics.sidebarCollapsed : Theme.Metrics.sidebarWidth,
               alignment: .topLeading)
        .animation(collapsedAnimation, value: collapsed)
    }

    private var collapsedAnimation: Animation? {
        reduceMotion ? nil : Theme.Motion.panel
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Kopf (Traffic-Light-Platz + Panel-Toggle)

    private var header: some View {
        HStack {
            if !collapsed { Spacer() }
            panelToggle
        }
        .frame(height: 34)
        .padding(.horizontal, collapsed ? 0 : 12)
        .padding(.top, 6)
    }

    private var panelToggle: some View {
        Button {
            withAnimation(collapsedAnimation) { collapsed.toggle() }
        } label: {
            Image(systemName: collapsed ? "sidebar.leading" : "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.Palette.text3)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                        .strokeBorder(Theme.Palette.linieSidebar, lineWidth: Theme.Metrics.hairline)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsed ? "Seitenleiste ausklappen" : "Seitenleiste einklappen")
    }

    // MARK: Wortmarke

    private var wordmarkRow: some View {
        Group {
            if collapsed {
                wordmarkBars(scale: 18.0 / 16.0)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 9) {
                    wordmarkBars(scale: 1)
                    Text("STASI")
                        .font(Theme.Typo.wordmark())
                        .tracking(2.4)
                        .foregroundColor(Theme.Palette.ink)
                }
                .padding(.horizontal, 11)
            }
        }
    }

    /// Drei Balken: durchgehend Akzent (v3), je 3 px breit.
    private func wordmarkBars(scale: CGFloat) -> some View {
        HStack(spacing: 2.5) {
            Capsule().fill(Theme.accent).frame(width: 3, height: 9 * scale)
            Capsule().fill(Theme.accent).frame(width: 3, height: 16 * scale)
            Capsule().fill(Theme.accent).frame(width: 3, height: 6 * scale)
        }
    }

    @ViewBuilder
    private var tagline: some View {
        if !collapsed {
            Text(Copy.tagline(settings))
                .font(Theme.Typo.counter(11))
                .foregroundColor(Theme.Palette.text3)
                .padding(.horizontal, 11)
                .padding(.top, 3)
        }
    }

    // MARK: Navigation

    private var navList: some View {
        VStack(alignment: .leading, spacing: collapsed ? 4 : 2) {
            ForEach(Self.navSections, id: \.self) { section in
                if collapsed {
                    collapsedTile(section)
                } else {
                    navRow(section)
                    if section == .bericht && selection.section == .protokolle {
                        protocolsSubrow
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    /// Aktive Zeile: Akzentfläche + weißer Text + Schatten (v3).
    private func navRow(_ section: AppSelection.Section) -> some View {
        let active = selection.section == section
        return Button {
            selection.section = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? .white : Theme.Palette.text3)
                    .frame(width: 20)
                Text(section.label)
                    .font(Theme.Typo.nav().weight(active ? .semibold : .regular))
                    .foregroundColor(active ? .white : Theme.Palette.text3)
                Spacer()
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 11)
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

    /// Unterzeile „Alle Protokolle" unter „Der Bericht" (Protokolle-Screen aktiv).
    private var protocolsSubrow: some View {
        Button {
            selection.section = .protokolle
        } label: {
            Text("Alle Protokolle")
                .font(Theme.Typo.secondary(size: 12.5).weight(.semibold))
                .foregroundColor(Theme.Palette.stempelrotDunkel)
                .padding(.top, 6)
                .padding(.bottom, 6)
                .padding(.leading, 22)
                .padding(.trailing, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Theme.Palette.stempelrot).frame(width: 3)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var settingsRow: some View {
        Group {
            if collapsed {
                collapsedTile(.einstellungen)
            } else {
                navRow(.einstellungen)
                    .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: Fußzeile

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.Palette.linieSidebar)
                .frame(height: Theme.Metrics.hairline)
            if collapsed {
                Text(AppVersion.display)
                    .font(Theme.Typo.counter(9))
                    .foregroundColor(Theme.Palette.text3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("v \(AppVersion.display) · AKTE \(AppVersion.akte)")
                    Text("© meder.dev")
                }
                .font(Theme.Typo.counter(10))
                .foregroundColor(Theme.Palette.text3)
                .lineSpacing(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: Eingeclippte Kacheln (38 × 38, Radius 8)

    @State private var hoveredTile: AppSelection.Section?

    private func collapsedTile(_ section: AppSelection.Section) -> some View {
        let active = selection.section == section
        let hovered = hoveredTile == section
        return Button {
            selection.section = section
        } label: {
            ZStack(alignment: .leading) {
                Image(systemName: section.icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(active ? Theme.Palette.stempelrot : Theme.Palette.text3.opacity(0.85))
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(active || hovered ? Theme.Palette.papier : Color.clear)
                            .shadow(color: active ? Color.black.opacity(0.06) : .clear,
                                    radius: 0, x: 1, y: 1)
                    )
                if hovered {
                    tooltip(section.label)
                        .fixedSize()
                        .offset(x: 46)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredTile = hovering ? section : nil
        }
    }

    /// Dunkler Tooltip rechts neben dem Symbol (nur eingeklappt).
    private func tooltip(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typo.secondary(size: 11.5).weight(.medium))
            .foregroundColor(Theme.Palette.dunkelText)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.Palette.dunkelGrund)
                    .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 6)
            )
    }
}
