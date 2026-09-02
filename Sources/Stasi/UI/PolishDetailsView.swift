import AppKit
import SwiftUI

/// Gemeinsamer klickbarer Badge für Bericht und Protokolle.
/// Das Popover lebt im normalen SwiftUI-Fenster, nie in einem NSPanel.
struct PolishBadge: View {
    let record: TranscriptionRecord
    var compact = false

    @State private var showingDetails = false

    @ViewBuilder
    var body: some View {
        if let summary = record.polish,
           let text = compact
            ? summary.compactBadgeText
            : summary.badgeText(correctionCount: record.corrections.count) {
            Button {
                showingDetails.toggle()
            } label: {
                Text(text)
                    .font(Theme.Typo.counter(10))
                    .monospacedDigit()
                    .foregroundColor(Theme.Palette.text3)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, compact ? 5 : 6)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.Palette.linieSidebar,
                                      lineWidth: Theme.Metrics.hairline))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("polish.details.showAccessibility"))
            .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                PolishDetailsPopover(record: record)
            }
        }
    }
}

private struct PolishDetailsPopover: View {
    let record: TranscriptionRecord

    private var sections: [PolishDetailSection] {
        record.polish?.detailSections(corrections: record.corrections) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("polish.title"))
                .font(Theme.Typo.sectionTitle())
                .foregroundColor(Theme.Palette.ink)

            if sections.isEmpty {
                Text(L10n.text("polish.details.legacyEmpty"))
                    .font(Theme.Typo.secondary(size: 12))
                    .foregroundColor(Theme.Palette.text2)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title.uppercased())
                                .font(Theme.Typo.kicker(size: 9.5))
                                .tracking(0.6)
                                .foregroundColor(Theme.Palette.text3)
                            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                Text(item)
                                    .font(Theme.Typo.body())
                                    .foregroundColor(Theme.Palette.ink)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            Divider().overlay(Theme.Palette.linieInnen)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(L10n.text("rawText.title.uppercase"))
                        .font(Theme.Typo.kicker(size: 9.5))
                        .tracking(0.6)
                        .foregroundColor(Theme.Palette.text3)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.rawText, forType: .string)
                    } label: {
                        Label(L10n.text("action.copy"), systemImage: "doc.on.doc")
                            .font(Theme.Typo.secondary(size: 11.5).weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.accent)
                    .accessibilityLabel(L10n.text("rawText.copy"))
                }
                ScrollView {
                    Text(record.rawText)
                        .font(Theme.Typo.body())
                        .foregroundColor(Theme.Palette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(Theme.Palette.surface)
    }
}
