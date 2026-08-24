import SwiftUI

// MARK: - Navigation

@MainActor
@Observable
final class AppSelection {
    var section: Section = .bericht
    static let shared = AppSelection()

    enum Section: String, CaseIterable, Identifiable {
        case bericht, protokolle, woerterbuch, einstellungen, konto
        var id: String { rawValue }

        var label: String {
            switch self {
            case .bericht: "Der Bericht"
            case .protokolle: "Protokolle"
            case .woerterbuch: "Wörterbuch"
            case .einstellungen: "Einstellungen"
            case .konto: "Konto"
            }
        }

        var icon: String {
            switch self {
            case .bericht: "chart.bar"
            case .protokolle: "doc.text"
            case .woerterbuch: "text.book.closed"
            case .einstellungen: "gearshape"
            case .konto: "person"
            }
        }
    }
}

// MARK: - Sidebar (212px)

struct SidebarView: View {
    @Environment(AppSelection.self) private var selection
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wordmark
            VStack(alignment: .leading, spacing: 2) {
                Text("STASI")
                    .font(Theme.Typo.wordmark())
                    .tracking(2)
                    .foregroundColor(Theme.Palette.ink)
                Text(Copy.tagline(settings))
                    .font(Theme.Typo.secondary())
                    .foregroundColor(Theme.Palette.sub)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)

            // Navigation
            VStack(spacing: 2) {
                ForEach(AppSelection.Section.allCases) { section in
                    navRow(section)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Erscheinungsbild & Akzentfarbe (Fußzeile)
            AppearanceMenu()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            // Versionszeile
            Text("v 0.9 · Akte 001 / © meder.dev")
                .font(Theme.Typo.kicker(size: 9))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundColor(Theme.Palette.sub.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(width: Theme.Metrics.sidebarWidth)
        .background(Theme.Palette.background)
    }

    private func navRow(_ section: AppSelection.Section) -> some View {
        let active = selection.section == section
        return Button {
            Task { @MainActor in selection.section = section }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .frame(width: 18)
                    .foregroundStyle(active ? Theme.accent.brightenedForDarkMode() : Theme.Palette.sub)
                Text(section.label)
                    .font(Theme.Typo.nav().weight(active ? .semibold : .regular))
                    .foregroundColor(active ? Theme.Palette.ink : Theme.Palette.ink.opacity(0.75))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(active ? Theme.tint(Theme.accent) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Erscheinungsbild-Menü (Theme + Akzentfarben)

struct AppearanceMenu: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        settings.appearance == .dark ||
        (settings.appearance == .system && colorScheme == .dark)
    }

    var body: some View {
        Menu {
            Section("Erscheinungsbild") {
                ForEach(SettingsStore.Appearance.allCases) { a in
                    Button {
                        settings.appearance = a
                    } label: {
                        if settings.appearance == a {
                            Label(a.label, systemImage: "checkmark")
                        } else {
                            Text(a.label)
                        }
                    }
                }
            }
            Section("Akzentfarbe") {
                ForEach(SettingsStore.accentPresets, id: \.1) { name, hex in
                    Button {
                        settings.accentHex = hex
                    } label: {
                        HStack {
                            Circle().fill(Color(stasiHex: hex)).frame(width: 10, height: 10)
                            if settings.accentHex == hex {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isDark ? "sun.max" : "moon")
                    .font(.system(size: 12))
                    .frame(width: 18)
                Text("Erscheinungsbild")
                    .font(Theme.Typo.secondary())
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.Palette.sub)
            }
            .foregroundColor(Theme.Palette.ink.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.Palette.surface)
            )
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
    }
}
