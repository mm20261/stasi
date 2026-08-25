import SwiftUI
import AppKit

// MARK: - Konto (v3: Profilkarte mit Kreis-Avatar)

struct AccountView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var nameDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("PERSONALAKTE")
                        .kicker(Theme.Palette.text3)
                    Text("Konto")
                        .font(Theme.Typo.h1())
                        .tracking(-0.6)
                        .foregroundColor(Theme.Palette.ink)
                    Text(Copy.accountSubtitle(settings))
                        .font(Theme.Typo.body())
                        .foregroundColor(Theme.Palette.text2)
                }

                VStack(alignment: .leading, spacing: 14) {
                    profileCard
                    signatureCard
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, Theme.Metrics.contentPaddingH)
            .padding(.bottom, 80)
            .frame(maxWidth: 560 + 2 * Theme.Metrics.contentPaddingH, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { nameDraft = settings.userName }
    }

    // MARK: Profil

    private var profileCard: some View {
        HStack(alignment: .top, spacing: 20) {
            Button {
                pickAvatar()
            } label: {
                // v3: Kreis-Avatar 72 px (Akzent-Tint, Akzent-Initiale),
                // „+"-Punkt unten rechts.
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let img = settings.avatarImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Theme.tint(Theme.accent))
                                .overlay(
                                    Text(String(settings.userName.first?.uppercased() ?? "S"))
                                        .font(Theme.Typo.avatarInitial())
                                        .foregroundStyle(Theme.accent)
                                )
                                .frame(width: 72, height: 72)
                        }
                    }
                    .overlay(
                        Circle().strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline)
                    )
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 22, height: 22)
                        .overlay(Text("+").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white))
                        .offset(x: 4, y: 4)
                }
                .frame(width: 76, height: 76)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(settings.avatarPath != nil ? "Bild ändern" : "Bild wählen")
            .accessibilityLabel(settings.avatarPath != nil ? "Profilbild ändern" : "Profilbild wählen")

            VStack(alignment: .leading, spacing: 0) {
                Text("NAME")
                    .kicker(Theme.Palette.text3)
                TextField("Wie sollen wir dich nennen?", text: $nameDraft)
                    .stasiInput()
                    .padding(.top, 6)
                    .onSubmit { commitName() }
                    .onChange(of: nameDraft) { _, newValue in
                        settings.userName = newValue.trimmingCharacters(in: .whitespaces)
                    }
                if settings.avatarPath != nil {
                    Button("Bild entfernen") {
                        settings.avatarPath = nil
                    }
                    .font(Theme.Typo.secondary())
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.Palette.stempelrot)
                    .padding(.top, 8)
                }
                Text("Kein Login, keine E-Mail — alles bleibt auf diesem Mac.")
                    .font(Theme.Typo.note())
                    .foregroundColor(Theme.Palette.text2)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card(padding: 20)
    }

    // MARK: Signaturkarte (dunkel)

    private var signatureCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("STASI · V \(AppVersion.display) · AKTE \(AppVersion.akte)")
                .font(Theme.Typo.counter(12).weight(.bold))
                .tracking(1.7)
                .textCase(.uppercase)
                .foregroundColor(Theme.Palette.dunkelText)
            Text(signatureNote)
                .font(Theme.Typo.caption())
                .foregroundColor(Theme.Palette.dunkelText2)
                .lineHeight()
                .padding(.top, 8)
            Link(destination: URL(string: "https://meder.dev")!) {
                Text("meder.dev")
                    .font(Theme.Typo.counter(11))
                    .foregroundColor(Theme.Palette.dunkelLink)
                    .padding(.bottom, 1)
                    .background(alignment: .bottom) {
                        Rectangle().fill(Theme.Palette.dunkelLink)
                            .frame(height: Theme.Metrics.hairline)
                    }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.radiusCard, style: .continuous)
                .fill(Theme.Palette.dunkelGrund)
        )
    }

    private var signatureNote: String {
        "Gebaut von meder.dev in Köln. Lokal, offline, ohne Konto."
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
