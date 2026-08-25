import SwiftUI

// MARK: - Wörterbuch (v2-Restyle, Tabs: Begriffe / Ersetzungen / Auto-gelernt)

struct DictionaryView: View {
    @Environment(AppState.self) private var app

    @State private var tab: Tab = .begriffe
    @State private var newTerm = ""
    @State private var newFrom = ""
    @State private var newTo = ""

    enum Tab: String, CaseIterable, Identifiable {
        case begriffe, ersetzungen, autoGelernt
        var id: String { rawValue }
        var label: String {
            switch self {
            case .begriffe: "Begriffe"
            case .ersetzungen: "Ersetzungen"
            case .autoGelernt: "Auto-gelernt"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                tabs
                content
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Wörterbuch")
                .font(Theme.Typo.h1())
                .tracking(-0.3)
                .foregroundColor(Theme.Palette.ink)
            Text("Eigene Begriffe, damit Stasi sie korrekt protokolliert.")
                .font(Theme.Typo.body())
                .foregroundColor(Theme.Palette.sub)
        }
    }

    // MARK: Segmented Tabs

    private var tabs: some View {
        HStack(spacing: 3) {
            ForEach(Tab.allCases) { tabItem in
                Button {
                    withAnimation(Theme.Motion.fast) { tab = tabItem }
                } label: {
                    Text(tabItem.label)
                        .font(Theme.Typo.secondary().weight(tab == tabItem ? .semibold : .regular))
                        .foregroundColor(tab == tabItem ? Theme.Palette.ink : Theme.Palette.sub)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(tab == tabItem ? Theme.Palette.surface : Color.clear)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.Palette.hover.opacity(0.5)))
        .overlay(Capsule().strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline))
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .begriffe: begriffeTab
        case .ersetzungen: ersetzungenTab
        case .autoGelernt: autoTab
        }
    }

    // MARK: Begriffe

    private var begriffeTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                TextField("Begriff hinzufügen — z. B. OnePage, Meta CAPI …", text: $newTerm)
                    .stasiInput()
                    .onSubmit { addTerm() }
                Button("Hinzufügen") { Task { @MainActor in addTerm() } }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            termList(type: .word) { entry in
                EditableTermRow(entry: entry) { updated in Task { @MainActor in app.dictionary.update(updated) } } onDelete: {
                    Task { @MainActor in app.dictionary.delete(entry) }
                }
            }
            if let err = app.dictionary.lastError {
                Text("⚠︎ \(err)").font(Theme.Typo.secondary()).foregroundColor(Theme.Palette.destructive)
            }
        }
    }

    private func addTerm() {
        let value = newTerm.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        var e = DictionaryEntry(type: .word, value: value)
        e.warns = CommonWords.warnings(for: e).isEmpty ? nil : CommonWords.warnings(for: e)
        app.dictionary.add(e)
        newTerm = ""
    }

    // MARK: Ersetzungen

    private var ersetzungenTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                TextField("Kürzel (gehört)", text: $newFrom)
                    .stasiInput()
                    .onSubmit { addReplacement() }
                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Palette.sub)
                TextField("Langform (geschrieben)", text: $newTo)
                    .stasiInput()
                    .onSubmit { addReplacement() }
                Button("Hinzufügen") { Task { @MainActor in addReplacement() } }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(newFrom.trimmingCharacters(in: .whitespaces).isEmpty
                              || newTo.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            termList(type: .correction) { entry in
                EditableReplacementRow(entry: entry) { updated in Task { @MainActor in app.dictionary.update(updated) } } onDelete: {
                    Task { @MainActor in app.dictionary.delete(entry) }
                }
            }
        }
    }

    private func addReplacement() {
        let from = newFrom.trimmingCharacters(in: .whitespaces)
        let to = newTo.trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty, !to.isEmpty else { return }
        var e = DictionaryEntry(type: .correction, from: from, to: to)
        let warns = CommonWords.warnings(for: e)
        e.warns = warns.isEmpty ? nil : warns
        app.dictionary.add(e)
        newFrom = ""
        newTo = ""
    }

    // MARK: Auto-gelernt

    private var autoTab: some View {
        let learned = app.dictionary.entries.filter { $0.type == .learned }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Begriffe, die Stasi beim Diktieren selbst entdeckt hat. Übernehmen oder ignorieren.")
                .font(Theme.Typo.secondary())
                .foregroundColor(Theme.Palette.sub)

            if learned.isEmpty {
                VStack(spacing: 4) {
                    Text("Alles gesichtet")
                        .font(Theme.Typo.body().weight(.medium))
                        .foregroundColor(Theme.Palette.ink)
                    Text("Keine neuen Vorschläge.")
                        .font(Theme.Typo.secondary())
                        .foregroundColor(Theme.Palette.sub)
                }
                .frame(maxWidth: .infinity)
                .card()
                .padding(.top, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(learned.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 10) {
                            Text(entry.value)
                                .font(Theme.Typo.body())
                                .foregroundColor(Theme.Palette.ink)
                            Spacer()
                            if let note = entry.note {
                                Text(note.uppercased())
                                    .kicker(Theme.Palette.sub)
                            }
                            Button("Übernehmen") { Task { @MainActor in app.dictionary.promote(entry) } }
                                .buttonStyle(GhostButtonStyle())
                            Button("Ignorieren") { Task { @MainActor in app.dictionary.delete(entry) } }
                                .buttonStyle(GhostButtonStyle())
                        }
                        .padding(.vertical, 10)
                        if index < learned.count - 1 { Divider().overlay(Theme.Palette.line) }
                    }
                }
                .card(padding: 14)
            }
        }
    }

    // MARK: Gemeinsame Listen-Card

    private func termList(type: EntryType,
                          @ViewBuilder row: @escaping (DictionaryEntry) -> some View) -> some View {
        let filtered = app.dictionary.entries.filter { $0.type == type }
        return Group {
            if filtered.isEmpty {
                emptyForCurrentTab
                    .frame(maxWidth: .infinity)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, entry in
                        row(entry)
                        if index < filtered.count - 1 {
                            Divider().overlay(Theme.Palette.line)
                        }
                    }
                }
                .card(padding: 6)
            }
        }
    }

    @ViewBuilder
    private var emptyForCurrentTab: some View {
        switch tab {
        case .begriffe:
            Text("Noch keine Begriffe. Füge Namen, Jargon, Produktnamen hinzu.")
                .font(Theme.Typo.secondary())
                .foregroundColor(Theme.Palette.sub)
                .padding(.vertical, 22)
        default:
            Text("Noch keine Ersetzungen. Beispiel: „cloud code“ → „Claude Code“.")
                .font(Theme.Typo.secondary())
                .foregroundColor(Theme.Palette.sub)
                .padding(.vertical, 22)
        }
    }
}

// MARK: - Icon-Button (28×28, Hover: Akzent bzw. Rot für Löschen)

struct RowIconButton: View {
    let symbol: String
    var destructive = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(hovered
                                 ? (destructive ? Theme.Palette.destructive : Theme.accent)
                                 : Theme.Palette.sub)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(hovered
                              ? (destructive ? Theme.Palette.destructive.opacity(0.08) : Theme.tint(Theme.accent))
                              : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(Theme.Motion.micro, value: hovered)
    }
}

// MARK: - Editierbare Zeilen

struct EditableTermRow: View {
    let entry: DictionaryEntry
    let onSave: (DictionaryEntry) -> Void
    let onDelete: () -> Void

    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 10) {
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.Typo.body())
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Theme.Palette.backgroundTop)
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Theme.accent, lineWidth: 1))
                    .onSubmit { commit() }
                Button("Speichern") { Task { @MainActor in commit() } }
                    .buttonStyle(AccentButtonStyle())
            } else {
                Text(entry.value)
                    .font(Theme.Typo.body())
                    .foregroundColor(Theme.Palette.ink)
                if let note = entry.note {
                    Text(note)
                        .font(Theme.Typo.secondary())
                        .foregroundColor(Theme.Palette.sub)
                }
                if let warns = entry.warns, !warns.isEmpty {
                    Label(warns.first ?? "", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundColor(Color(stasiHex: 0xDA8B27))
                }
            }
            Spacer()
            RowIconButton(symbol: editing ? "checkmark" : "pencil",
                          action: editing ? { commit() } : { startEdit() })
            RowIconButton(symbol: "trash", destructive: true, action: onDelete)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func startEdit() { draft = entry.value; editing = true }
    private func commit() {
        let v = draft.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty && v != entry.value {
            var e = entry; e.value = v; onSave(e)
        }
        editing = false
    }
}

struct EditableReplacementRow: View {
    let entry: DictionaryEntry
    let onSave: (DictionaryEntry) -> Void
    let onDelete: () -> Void

    @State private var editing = false
    @State private var draftFrom = ""
    @State private var draftTo = ""

    var body: some View {
        HStack(spacing: 10) {
            if editing {
                TextField("", text: $draftFrom)
                    .textFieldStyle(.plain)
                    .font(Theme.Typo.counter())
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Theme.Palette.backgroundTop)
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Theme.accent, lineWidth: 1))
                Image(systemName: "arrow.right").font(.system(size: 11)).foregroundColor(Theme.Palette.sub)
                TextField("", text: $draftTo)
                    .textFieldStyle(.plain)
                    .font(Theme.Typo.body())
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Theme.Palette.backgroundTop)
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Theme.accent, lineWidth: 1))
                Button("Speichern") { Task { @MainActor in commit() } }
                    .buttonStyle(AccentButtonStyle())
            } else {
                Text(entry.matchSource)
                    .font(Theme.Typo.counter(11.5))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.Palette.hover)
                    .cornerRadius(6)
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundColor(Theme.Palette.sub)
                Text(entry.replacementTarget)
                    .font(Theme.Typo.body())
                    .foregroundColor(Theme.Palette.ink)
                if let warns = entry.warns, !warns.isEmpty {
                    Label(warns.first ?? "", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundColor(Color(stasiHex: 0xDA8B27))
                }
            }
            Spacer()
            RowIconButton(symbol: editing ? "checkmark" : "pencil",
                          action: editing ? { commit() } : { startEdit() })
            RowIconButton(symbol: "trash", destructive: true, action: onDelete)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func startEdit() { draftFrom = entry.matchSource; draftTo = entry.replacementTarget; editing = true }
    private func commit() {
        let f = draftFrom.trimmingCharacters(in: .whitespaces)
        let t = draftTo.trimmingCharacters(in: .whitespaces)
        if !f.isEmpty && !t.isEmpty && (f != entry.matchSource || t != entry.replacementTarget) {
            var e = entry; e.from = f; e.to = t; onSave(e)
        }
        editing = false
    }
}
