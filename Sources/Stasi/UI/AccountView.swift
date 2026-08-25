import SwiftUI
import AppKit

// MARK: - Konto (v2)

struct AccountView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var nameDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Konto")
                        .font(Theme.Typo.h1())
                        .tracking(-0.3)
                        .foregroundColor(Theme.Palette.ink)
                    Text(kontoSubtitle)
                        .font(Theme.Typo.body())
                        .foregroundColor(Theme.Palette.sub)
                }

                VStack(alignment: .leading, spacing: 14) {
                    profileCard
                    signatureCard
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { nameDraft = settings.userName }
    }

    private var kontoSubtitle: String {
        settings.ironyOn
            ? "Deine Akte. Ausnahmsweise führst du sie selbst."
            : "Dein Profil — lokal gespeichert."
    }

    // MARK: Profil

    private var profileCard: some View {
        HStack(spacing: 20) {
            Button {
                pickAvatar()
            } label: {
                avatarOrInitials
                    .frame(width: 72, height: 72)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(settings.avatarPath != nil ? "Bild ändern" : "Bild wählen")

            VStack(alignment: .leading, spacing: 0) {
                Text("NAME")
                    .kicker(Theme.Palette.sub)
                TextField("Wie sollen wir dich nennen?", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.custom("Geist", size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.Palette.backgroundTop)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline))
                    .padding(.top, 6)
                    .onSubmit { commitName() }
                    .onChange(of: nameDraft) { _, newValue in
                        settings.userName = newValue.trimmingCharacters(in: .whitespaces)
                    }
                if settings.avatarPath != nil {
                    Button("Bild entfernen", role: .destructive) {
                        settings.avatarPath = nil
                    }
                    .font(Theme.Typo.secondary())
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.Palette.destructive)
                    .padding(.top, 6)
                }
                Text("Kein Login, keine E-Mail — alles bleibt auf diesem Mac.")
                    .font(.custom("Geist", size: 11.5))
                    .foregroundColor(Theme.Palette.sub)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card(padding: 20)
    }

    @ViewBuilder
    private var avatarOrInitials: some View {
        if let img = settings.avatarImage {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline))
        } else {
            ZStack {
                Circle().fill(Theme.tint(Theme.accent))
                Text(String(settings.userName.first?.uppercased() ?? "S"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    // MARK: Signatur

    private var signatureCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("STASI · V 0.9 · AKTE 001")
                .kicker(Theme.Palette.sub)
            Text(signatureNote)
                .font(.custom("Geist", size: 12))
                .foregroundColor(Theme.Palette.sub)
                .lineHeight()
                .padding(.top, 6)
            Link(destination: URL(string: "https://meder.dev")!) {
                Text("meder.dev ↗")
                    .font(.custom("Geist", size: 12.5).weight(.semibold))
                    .foregroundColor(Theme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 18)
    }

    private var signatureNote: String {
        settings.ironyOn
            ? "Gebaut von meder.dev. Weitergeben erlaubt. Zuhören sowieso."
            : "Gebaut von meder.dev."
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
