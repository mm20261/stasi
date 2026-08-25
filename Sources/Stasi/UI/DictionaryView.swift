import SwiftUI

// MARK: - Wörterbuch (v3: Segmented-Tabs)

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
            case .begriffe: "BEGRIFFE"
            case .ersetzungen: "ERSETZUNGEN"
            case .autoGelernt: "AUTO-GELERNT"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("SPRACHREGISTER")
                        .kicker(Theme.Palette.text3)
                    Text("Wörterbuch")
                        .font(Theme.Typo.h1())
                        .tracking(-0.6)
                        .foregroundColor(Theme.Palette.ink)
                    Text("Eigene Begriffe, damit Stasi sie korrekt protokolliert.")
                        .font(Theme.Typo.body())
                        .foregroundColor(Theme.Palette.text2)
                }

                tabs
                    .padding(.top, 20)
                content
                    .padding(.top, 0)
            }
            .padding(.horizontal, Theme.Metrics.contentPaddingH)
            .padding(.bottom, 80)
            .frame(maxWidth: 620 + 2 * Theme.Metrics.contentPaddingH, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { app.refreshPermissionState() }
    }

    // MARK: Segmented-Tabs (v3: Akzent-Knopf auf hover-Track)

    private func count(for tab: Tab) -> Int {
        switch tab {
        case .begriffe: app.dictionary.entries.filter { $0.type == .word }.count
        case .ersetzungen: app.dictionary.entries.filter { $0.type == .correction }.count
        case .autoGelernt: app.dictionary.entries.filter { $0.type == .learned }.count
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { tabItem in
                let active = tab == tabItem
                Button {
                    withAnimation(Theme.Motion.fast) { tab = tabItem }
                } label: {
                    Text("\(tabItem.label) · \(Copy.formatGermanNumber(count(for: tabItem)))")
                        .font(Theme.Typo.counter(11))
                        .monospacedDigit()
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundColor(active ? .white : Theme.Palette.text3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(active ? Theme.accent : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
            Spacer()
        }
        .padding(3)
        .background(Theme.Palette.hover, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch tab {
            case .begriffe: begriffeTab
            case .ersetzungen: ersetzungenTab
            case .autoGelernt: autoTab
            }
        }
        .padding(.top, 16)
    }

    // MARK: Begriffe

    private var begriffeTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                TextField("Begriff hinzufügen — z. B. OnePage, Meta CAPI …", text: $newTerm)
                    .stasiInput()
                    .onSubmit { addTerm() }
                    .frame(maxWidth: 380)
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
                    .foregroundColor(Theme.Palette.text3)
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
                .foregroundColor(Theme.Palette.text2)

            if learned.isEmpty {
                // Leerzustand als Fußzeile: „ALLES GESICHTET"
                Text("ALLES GESICHTET")
                    .font(Theme.Typo.kicker(size: 10))
                    .tracking(1.2)
                    .foregroundColor(Theme.Palette.text3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .background(
                        Rectangle()
                            .fill(Theme.Palette.zeileHover)
                            .overlay(alignment: .top) {
                                Rectangle().fill(Theme.Palette.linieInnen)
                                    .frame(height: Theme.Metrics.hairline)
                            }
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(learned.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 10) {
                            Text(entry.value)
                                .font(Theme.Typo.body())
                                .foregroundColor(Theme.Palette.ink)
                            if let note = entry.note {
                                Text(note.uppercased())
                                    .font(Theme.Typo.counter(10))
                                    .foregroundColor(Theme.Palette.text3)
                            }
                            Spacer()
                            Button("ÜBERNEHMEN") {
                                Task { @MainActor in app.dictionary.promote(entry) }
                            }
                            .font(Theme.Typo.kicker(size: 10.5))
                            .tracking(0.8)
                            .foregroundColor(Theme.Palette.archivgruen)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .overlay(RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Theme.Palette.archivgruen, lineWidth: Theme.Metrics.hairline))
                            .buttonStyle(.plain)
                            Button("IGNORIEREN") {
                                Task { @MainActor in app.dictionary.delete(entry) }
                            }
                            .font(Theme.Typo.kicker(size: 10.5))
                            .tracking(0.8)
                            .foregroundColor(Theme.Palette.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.Palette.chip))
                            .overlay(RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Theme.Palette.linieSidebar, lineWidth: Theme.Metrics.hairline))
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        if index < learned.count - 1 {
                            Divider().overlay(Theme.Palette.linieInnen)
                        }
                    }
                }
                .card(padding: 0)
            }
        }
    }

    // MARK: Gemeinsame Listen-Karte (Hauptkarte mit Index-Spalte)

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
                        HStack(alignment: .center, spacing: 0) {
                            Text(String(format: "%02d", index + 1))
                                .font(Theme.Typo.counter(10))
                                .monospacedDigit()
                                .foregroundColor(Theme.Palette.text3.opacity(0.75))
                                .frame(width: 26)
                                .padding(.leading, 16)
                            row(entry)
                        }
                        if index < filtered.count - 1 {
                            Divider().overlay(Theme.Palette.linieInnen)
                                .padding(.leading, 42)
                        }
                    }
                }
                .card(padding: 0)
            }
        }
    }

    @ViewBuilder
    private var emptyForCurrentTab: some View {
        switch tab {
        case .begriffe:
            Text("Noch keine Begriffe. Füge Namen, Jargon, Produktnamen hinzu.")
                .font(Theme.Typo.secondary())
                .foregroundColor(Theme.Palette.text2)
                .padding(.vertical, 22)
        default:
            Text("Noch keine Ersetzungen. Beispiel: „cloud code“ → „Claude Code“.")
                .font(Theme.Typo.secondary())
                .foregroundColor(Theme.Palette.text2)
                .padding(.vertical, 22)
        }
    }
}

// MARK: - Icon-Button (26×26; Mülleimer-Hover warnFlaeche/stempelrot)

struct RowIconButton: View {
    let symbol: String
    var destructive = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(hovered && destructive
                                 ? Theme.Palette.destructive
                                 : hovered ? Theme.Palette.ink : Theme.Palette.text3)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metrics.radiusControl)
                        .fill(hovered && destructive
                              ? Theme.Palette.warnFlaeche
                              : hovered ? Theme.Palette.chip : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName)
        .onHover { hovered = $0 }
        .animation(Theme.Motion.micro, value: hovered)
    }

    private var accessibilityName: String {
        switch symbol {
        case "pencil": "Bearbeiten"
        case "trash": "Löschen"
        case "checkmark": "Änderung übernehmen"
        default: symbol
        }
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.Palette.zeileHover)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput)
                        .strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline))
                    .onSubmit { commit() }
                    .frame(maxWidth: 320)
                Button("SPEICHERN") { Task { @MainActor in commit() } }
                    .font(Theme.Typo.kicker(size: 11))
                    .tracking(0.8)
                    .foregroundColor(Theme.Palette.archivgruen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.Palette.archivgruen, lineWidth: Theme.Metrics.hairline))
                    .buttonStyle(.plain)
            } else {
                Text(entry.value)
                    .font(Theme.Typo.body())
                    .foregroundColor(Theme.Palette.ink)
                if let note = entry.note {
                    Text(note)
                        .font(Theme.Typo.secondary(size: 11.5))
                        .foregroundColor(Theme.Palette.text2)
                }
                if let warns = entry.warns, !warns.isEmpty {
                    Label(warns.first ?? "", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundColor(Theme.Palette.warning)
                }
            }
            Spacer()
            RowIconButton(symbol: editing ? "checkmark" : "pencil",
                          action: editing ? { commit() } : { startEdit() })
            RowIconButton(symbol: "trash", destructive: true, action: onDelete)
        }
        .padding(.leading, 0)
        .padding(.trailing, 12)
        .padding(.vertical, 9)
        .background(editing ? Theme.Palette.zeileHover : Color.clear)
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.Palette.zeileHover)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput)
                        .strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline))
                    .frame(maxWidth: 140)
                Image(systemName: "arrow.right").font(.system(size: 11)).foregroundColor(Theme.Palette.text3)
                TextField("", text: $draftTo)
                    .textFieldStyle(.plain)
                    .font(Theme.Typo.body())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.Palette.zeileHover)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radiusInput)
                        .strokeBorder(Theme.Palette.line, lineWidth: Theme.Metrics.hairline))
                    .onSubmit { commit() }
                    .frame(maxWidth: 280)
                Button("SPEICHERN") { Task { @MainActor in commit() } }
                    .font(Theme.Typo.kicker(size: 11))
                    .tracking(0.8)
                    .foregroundColor(Theme.Palette.archivgruen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.Palette.archivgruen, lineWidth: Theme.Metrics.hairline))
                    .buttonStyle(.plain)
            } else {
                // Kürzel als Akzent-Tint-Chip (v3)
                Text(entry.matchSource)
                    .font(Theme.Typo.counter(11))
                    .foregroundColor(Theme.Palette.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.tint(Theme.accent)))
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundColor(Theme.Palette.text3)
                Text(entry.replacementTarget)
                    .font(Theme.Typo.body())
                    .foregroundColor(Theme.Palette.ink)
                if let warns = entry.warns, !warns.isEmpty {
                    Label(warns.first ?? "", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundColor(Theme.Palette.warning)
                }
            }
            Spacer()
            RowIconButton(symbol: editing ? "checkmark" : "pencil",
                          action: editing ? { commit() } : { startEdit() })
            RowIconButton(symbol: "trash", destructive: true, action: onDelete)
        }
        .padding(.leading, 0)
        .padding(.trailing, 12)
        .padding(.vertical, 9)
        .background(editing ? Theme.Palette.zeileHover : Color.clear)
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
