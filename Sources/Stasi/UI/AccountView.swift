import SwiftUI
import AppKit

// MARK: - Konto

struct AccountView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var nameDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Konto")
                        .font(Theme.Typo.h1())
                        .tracking(-0.3)
                        .foregroundColor(Theme.Palette.ink)
                    Text("Deine Akte. Ausnahmsweise führst du sie selbst.")
                        .font(Theme.Typo.secondary())
                        .foregroundColor(Theme.Palette.sub)
                }

                VStack(alignment: .leading, spacing: 22) {
                    // Profil
                    HStack(spacing: 18) {
                        avatarOrInitials
                            .frame(width: 76, height: 76)

                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Name", text: $nameDraft)
                                .textFieldStyle(.plain)
                                .font(Theme.Typo.body())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Theme.Palette.hover.opacity(0.6))
                                .cornerRadius(Theme.Metrics.radiusControl)
                                .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                                    .strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline))
                                .onSubmit { commitName() }
                                .onChange(of: nameDraft) { _, newValue in
                                    settings.userName = newValue.trimmingCharacters(in: .whitespaces)
                                }
                            Button("Bild wählen…") { pickAvatar() }
                                .buttonStyle(GhostButtonStyle())
                            if settings.avatarPath != nil {
                                Button("Bild entfernen", role: .destructive) {
                                    settings.avatarPath = nil
                                }
                                .font(Theme.Typo.secondary())
                                .buttonStyle(.plain)
                                .foregroundColor(Theme.Palette.destructive)
                            }
                        }
                    }

                    Text("Kein Login, keine E-Mail — alles bleibt auf diesem Mac.")
                        .font(Theme.Typo.kicker(size: 10))
                        .tracking(0.2)
                        .foregroundColor(Theme.Palette.sub.opacity(0.85))

                    Divider().overlay(Theme.Palette.line)

                    // Signatur
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Stasi · v 0.9 · Akte 001")
                            .font(Theme.Typo.counter(11.5))
                            .foregroundColor(Theme.Palette.sub)
                        Text("Gebaut von meder.dev. Weitergeben erlaubt. Zuhören sowieso.")
                            .font(Theme.Typo.body())
                            .lineHeight()
                            .foregroundColor(Theme.Palette.ink.opacity(0.9))
                        Link("meder.dev", destination: URL(string: "https://meder.dev")!)
                            .font(Theme.Typo.secondary())
                            .foregroundColor(Theme.accent.brightenedForDarkMode())
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { nameDraft = settings.userName }
    }

    @ViewBuilder
    private var avatarOrInitials: some View {
        if let img = settings.avatarImage {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 76, height: 76)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline))
        } else {
            ZStack {
                Circle().fill(Theme.tint(Theme.accent))
                Text(String(settings.userName.first?.uppercased() ?? "?"))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent.brightenedForDarkMode())
            }
        }
    }

    private func commitName() {
        settings.userName = nameDraft.trimmingCharacters(in: .whitespaces)
    }

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.copyAvatarToAppSupport(from: url)
        }
    }
}
