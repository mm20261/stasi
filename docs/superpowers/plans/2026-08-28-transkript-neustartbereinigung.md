# Transkript-Neustartbereinigung Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gesprochene explizite und markerlose Fehlstarts vollständig lokal erkennen, den späteren Versuch behalten und den unveränderten Rohtext im Verlauf sichern.

**Architecture:** `SelfCorrectionResolver` wird in zwei einmalige Pässe geteilt. Der erste Pass erweitert die vorhandene Markerlogik. Der zweite Pass erkennt nahe wiederholte Satzanfänge innerhalb derselben Aussage. Beide Pässe liefern weiterhin `Edit`-Einträge; `TranscriptPolisher` und `AppState` behalten ihre bestehenden Schnittstellen.

**Tech Stack:** Swift 6.2, Foundation, XCTest, Swift Package Manager, macOS 26

**Spec:** `docs/superpowers/specs/2026-08-28-transkript-release-und-autorenbereinigung-design.md`

## Global Constraints

- Vollständig lokal und regelbasiert; kein Apple-Foundation-Models-Rewrite und kein Cloud-Dienst.
- Unterstützte Polisher-Sprachen bleiben Deutsch und Englisch; `.other` bleibt unverändert geschützt.
- Der öffentliche Resolver-Vertrag bleibt `static func resolve(_ input: String, locale: PolishLocale) -> Result`.
- `TranscriptionRecord.rawText` bleibt unverändert; nur `correctedText` erhält die Bereinigung.
- Keine Änderung an History-Schema, UI, `TranscriptionEngine` oder `TextInjector`.
- Keine Bereinigung über `.`, `!` oder `?`.
- Bestehende Negations-, Quantifizierungs-, Fragen-, Namen- und Satzgrenzen-Tests dürfen nicht abgeschwächt werden.
- Markerlose Erkennung benötigt mindestens drei gemeinsame Anfangswörter.
- Suchfenster und Kandidatenzahl sind fest begrenzt.
- Jeder Task endet grün und wird separat reviewt.

---

### Task 1: Explizite Mehrwort-Neustarts erkennen

**Files:**
- Modify: `Sources/Stasi/Core/SelfCorrectionResolver.swift:19-111`
- Test: `Tests/StasiTests/SelfCorrectionResolverTests.swift:9-167`

**Interfaces:**
- Consumes: `PolishLocale.strongMarkers`, `weakMarkers`, `markerModifiers`, `protectedFrameWords`, `subjectPronouns`, `commonVerbs`
- Produces: unverändertes `SelfCorrectionResolver.Result`; neu intern `PassResult`, `AttemptMatch`, `resolveExplicitCorrections(in:locale:)`, `matchingRepeatedAttempt(tokens:before:after:locale:)`

- [ ] **Step 1: Zwei fehlschlagende Regressionstests ergänzen**

Füge vor dem Ende von `SelfCorrectionResolverTests` ein:

```swift
func testStrongMarkerAllowsIdenticalFrameWithRightContinuation() {
    let result = SelfCorrectionResolver.resolve(
        "Hallo, mein Name ist, nein, Hallo, mein Name ist Philipp",
        locale: .de
    )

    XCTAssertEqual(result.text, "Hallo, mein Name ist Philipp")
    XCTAssertEqual(result.resolvedCount, 1)
    XCTAssertEqual(result.edits, [
        SelfCorrectionResolver.Edit(
            removed: "Hallo mein Name ist",
            kept: "Hallo mein Name ist Philipp"
        ),
    ])
}

func testWeakMarkerAllowsMultiwordReplacementInRepeatedFrame() {
    let result = SelfCorrectionResolver.resolve(
        "Wir treffen uns Montag um zehn, ich meine, Wir treffen uns Dienstag um zwölf",
        locale: .de
    )

    XCTAssertEqual(result.text, "Wir treffen uns Dienstag um zwölf")
    XCTAssertEqual(result.resolvedCount, 1)
    XCTAssertEqual(result.edits, [
        SelfCorrectionResolver.Edit(
            removed: "Wir treffen uns Montag um zehn",
            kept: "Wir treffen uns Dienstag um zwölf"
        ),
    ])
}
```

- [ ] **Step 2: Nur die neuen Tests ausführen und Rot bestätigen**

Run:

```bash
swift test --filter 'StasiTests.SelfCorrectionResolverTests/(testStrongMarkerAllowsIdenticalFrameWithRightContinuation|testWeakMarkerAllowsMultiwordReplacementInRepeatedFrame)'
```

Expected: beide Tests schlagen fehl; der Text bleibt derzeit unverändert.

- [ ] **Step 3: Interne Pass-Typen und feste Grenzen ergänzen**

Ergänze in `SelfCorrectionResolver` direkt nach `Removal`:

```swift
private static let minimumRepeatedPrefixWords = 3
private static let maximumRepeatedPrefixWords = 12
private static let maximumRestartWindowWords = 16
private static let maximumRestartCandidatesPerSentence = 32

private struct PassResult {
    let text: String
    let edits: [Edit]
}

private struct AttemptMatch {
    let leftRange: Range<Int>
    let rightRange: Range<Int>
    let sharedPrefixWords: Int
}
```

- [ ] **Step 4: Den bestehenden Markerpass kapseln**

Ändere `resolve` zum Orchestrator:

```swift
static func resolve(_ input: String, locale: PolishLocale) -> Result {
    guard locale != .other, !input.isEmpty else {
        return Result(text: input, resolvedCount: 0, edits: [])
    }

    let explicit = resolveExplicitCorrections(in: input, locale: locale)
    return Result(
        text: explicit.text,
        resolvedCount: explicit.edits.count,
        edits: explicit.edits
    )
}
```

Verschiebe den bisherigen Inhalt aus `resolve` ab `var removals` bis zur Anwendung der Löschungen in diese Funktion:

```swift
private static func resolveExplicitCorrections(
    in input: String,
    locale: PolishLocale
) -> PassResult {
    var removals: [Removal] = []

    for sentence in sentences(in: input) where !sentence.endsWithQuestion {
        let tokens = tokenize(input, in: sentence.range)
        guard tokens.count >= 3 else { continue }
        let markers = findMarkers(in: tokens, locale: locale)
        guard !markers.isEmpty else { continue }

        for (index, marker) in markers.enumerated() {
            let previousBoundary = index == 0 ? 0 : markers[index - 1].span.upperBound
            let nextBoundary = index + 1 == markers.count
                ? tokens.count : markers[index + 1].span.lowerBound
            let before = previousBoundary..<marker.span.lowerBound
            let after = marker.span.upperBound..<nextBoundary

            guard !before.isEmpty, !after.isEmpty else { continue }

            if let attempt = matchingRepeatedAttempt(
                tokens: tokens,
                before: before,
                after: after,
                locale: locale
            ) {
                let removalRange = tokens[attempt.leftRange.lowerBound].range.lowerBound
                    ..<tokens[attempt.rightRange.lowerBound].range.lowerBound
                removals.append(Removal(
                    range: removalRange,
                    edit: Edit(
                        removed: phrase(tokens: tokens, range: attempt.leftRange, in: input),
                        kept: phrase(tokens: tokens, range: attempt.rightRange, in: input)
                    )
                ))
                continue
            }

            guard !startsCompleteSentence(tokens: tokens, range: after, locale: locale) else {
                continue
            }

            if let frame = matchingFrame(
                tokens: tokens,
                before: before,
                after: after,
                locale: locale
            ) {
                let leftRange = frame.leftStart..<marker.span.lowerBound
                let rightRange = after.startIndex..<(after.startIndex + frame.length)
                let removalRange = tokens[frame.leftStart].range.lowerBound
                    ..<tokens[after.lowerBound].range.lowerBound
                removals.append(Removal(
                    range: removalRange,
                    edit: Edit(
                        removed: phrase(tokens: tokens, range: leftRange, in: input),
                        kept: phrase(tokens: tokens, range: rightRange, in: input)
                    )
                ))
                continue
            }

            guard marker.strength == .strong,
                  let left = tokens[safe: before.index(before.endIndex, offsetBy: -1)],
                  let right = tokens[safe: after.startIndex],
                  left.normalized != right.normalized,
                  let leftClass = tokenClass(left.normalized, locale: locale),
                  leftClass == tokenClass(right.normalized, locale: locale)
            else { continue }

            removals.append(Removal(
                range: left.range.lowerBound..<right.range.lowerBound,
                edit: Edit(
                    removed: String(input[left.range]),
                    kept: String(input[right.range])
                )
            ))
        }
    }

    return applying(nonOverlapping(removals), to: input)
}
```

Ergänze den gemeinsamen Anwender:

```swift
private static func applying(_ removals: [Removal], to input: String) -> PassResult {
    guard !removals.isEmpty else {
        return PassResult(text: input, edits: [])
    }

    var output = input
    for removal in removals.reversed() {
        output.replaceSubrange(removal.range, with: "")
    }
    return PassResult(
        text: compactAfterRemoval(output),
        edits: removals.map(\.edit)
    )
}
```

- [ ] **Step 5: Wiederholte explizite Versuche konkret erkennen**

Ergänze:

```swift
private static func matchingRepeatedAttempt(
    tokens: [Token],
    before: Range<Int>,
    after: Range<Int>,
    locale: PolishLocale
) -> AttemptMatch? {
    let firstLeftStart = max(before.lowerBound, before.upperBound - maximumRestartWindowWords)
    var best: AttemptMatch?

    for leftStart in firstLeftStart..<before.upperBound {
        let leftCount = before.upperBound - leftStart
        let comparable = min(maximumRepeatedPrefixWords, leftCount, after.count)
        guard comparable >= minimumRepeatedPrefixWords else { continue }

        var prefix = 0
        while prefix < comparable,
              tokens[leftStart + prefix].normalized
                == tokens[after.lowerBound + prefix].normalized {
            prefix += 1
        }
        guard prefix >= minimumRepeatedPrefixWords else { continue }

        let exactLeftPrefix = prefix == leftCount
        if exactLeftPrefix {
            guard after.count > leftCount else { continue }
        } else {
            guard after.count > prefix else { continue }
            let comparedRemainder = min(leftCount, after.count)
            let hasProtectedDifference = (prefix..<comparedRemainder).contains { offset in
                let left = tokens[leftStart + offset].normalized
                let right = tokens[after.lowerBound + offset].normalized
                return left != right
                    && (locale.protectedFrameWords.contains(left)
                        || locale.protectedFrameWords.contains(right))
            }
            guard !hasProtectedDifference else { continue }
        }

        let keptLength = min(
            after.count,
            max(leftCount, prefix + 1)
        )
        let candidate = AttemptMatch(
            leftRange: leftStart..<before.upperBound,
            rightRange: after.lowerBound..<(after.lowerBound + keptLength),
            sharedPrefixWords: prefix
        )

        if let current = best {
            if candidate.sharedPrefixWords > current.sharedPrefixWords
                || (candidate.sharedPrefixWords == current.sharedPrefixWords
                    && candidate.leftRange.lowerBound > current.leftRange.lowerBound) {
                best = candidate
            }
        } else {
            best = candidate
        }
    }

    return best
}
```

Wichtig: Der Aufruf liegt vor `startsCompleteSentence`. Nur ein klarer gemeinsamer Rahmen darf diesen Schutz überstimmen.

- [ ] **Step 6: Explizite Tests und bestehende Sicherheitsverträge ausführen**

Run:

```bash
swift test --filter 'StasiTests.SelfCorrectionResolverTests'
```

Expected: alle neuen und bestehenden Resolver-Tests bestehen.

- [ ] **Step 7: Commit erstellen**

```bash
git add Sources/Stasi/Core/SelfCorrectionResolver.swift \
  Tests/StasiTests/SelfCorrectionResolverTests.swift
git commit -m $'feat(polish): erkenne explizite Neustarts\n\nCo-Authored-By: Claude <noreply@anthropic.com>'
```

---

### Task 2: Markerlose wiederholte Satzanfänge erkennen

**Files:**
- Modify: `Sources/Stasi/Core/SelfCorrectionResolver.swift`
- Test: `Tests/StasiTests/SelfCorrectionResolverTests.swift`

**Interfaces:**
- Consumes: `PassResult` und `applying(_:to:)` aus Task 1
- Produces: `resolveMarkerlessRestarts(in:locale:)`, `RestartCandidate`, begrenzte Kandidatensuche; `resolve` kombiniert beide Pass-Ergebnisse

- [ ] **Step 1: Positive markerlose Tests ergänzen**

Füge ein:

```swift
func testMarkerlessGermanRestartKeepsLaterAttempt() {
    let result = SelfCorrectionResolver.resolve(
        "Hallo, mein Name ist Peter, Hallo, mein Name ist Philipp",
        locale: .de
    )

    XCTAssertEqual(result.text, "Hallo, mein Name ist Philipp")
    XCTAssertEqual(result.resolvedCount, 1)
    XCTAssertEqual(result.edits.first?.removed, "Hallo mein Name ist Peter")
    XCTAssertEqual(result.edits.first?.kept, "Hallo mein Name ist Philipp")
}

func testMarkerlessExactPrefixRequiresIncompleteFirstAttempt() {
    XCTAssertEqual(
        resolve("Hallo, mein Name ist, Hallo, mein Name ist Philipp"),
        "Hallo, mein Name ist Philipp"
    )
}

func testMarkerlessEnglishRestartKeepsLaterAttempt() {
    XCTAssertEqual(
        resolve("We will meet on Friday, We will meet on Thursday", .en),
        "We will meet on Thursday"
    )
}

func testMarkerlessRestartAcceptsEmDashSeparator() {
    XCTAssertEqual(
        resolve("Wir treffen uns Montag — Wir treffen uns Dienstag"),
        "Wir treffen uns Dienstag"
    )
}

func testTwoMarkerlessRestartsEndAtLastAttempt() {
    let result = SelfCorrectionResolver.resolve(
        "Hallo mein Name ist Peter, Hallo mein Name ist Paul, Hallo mein Name ist Philipp",
        locale: .de
    )

    XCTAssertEqual(result.text, "Hallo mein Name ist Philipp")
    XCTAssertEqual(result.resolvedCount, 2)
    XCTAssertEqual(result.edits.map(\.removed), [
        "Hallo mein Name ist Peter",
        "Hallo mein Name ist Paul",
    ])
    XCTAssertEqual(result.edits.map(\.kept), [
        "Hallo mein Name ist Paul",
        "Hallo mein Name ist Philipp",
    ])
}
```

- [ ] **Step 2: Negative Schutztests ergänzen**

Füge ein:

```swift
func testCompleteMarkerlessRepetitionRemains() {
    let text = "Hallo mein Name ist Philipp, Hallo mein Name ist Philipp"
    XCTAssertEqual(resolve(text), text)
}

func testCompleteRepetitionWithLaterContinuationRemains() {
    let text = "Hallo mein Name ist Philipp, Hallo mein Name ist Philipp und ich wohne in Berlin"
    XCTAssertEqual(resolve(text), text)
}

func testMarkerlessRestartDoesNotCrossSentenceBoundary() {
    let text = "Hallo mein Name ist Peter. Hallo mein Name ist Philipp."
    XCTAssertEqual(resolve(text), text)
}

func testMarkerlessRestartDoesNotModifyQuestion() {
    let text = "Hallo mein Name ist Peter, Hallo mein Name ist Philipp?"
    XCTAssertEqual(resolve(text), text)
}

func testQuotedAndAnnouncedRepetitionRemains() {
    let text = "Ich sage „Hallo, mein Name ist Peter“ und wiederhole „Hallo, mein Name ist Philipp“."
    XCTAssertEqual(resolve(text), text)
}

func testAnnouncementInsideCandidateBlocksRemoval() {
    let text = "Hallo mein Name ist Peter und ich wiederhole Hallo mein Name ist Philipp"
    XCTAssertEqual(resolve(text), text)
}

func testTwoCommonWordsAreNotEnoughForMarkerlessRestart() {
    let text = "Mein Name ist Peter, Mein Name lautet Philipp"
    XCTAssertEqual(resolve(text), text)
}

func testMarkerlessSearchStopsOutsideFixedWindow() {
    let gap = (0..<20).map { "zwischen\($0)" }.joined(separator: " ")
    let text = "Hallo mein Name ist Peter \(gap) Hallo mein Name ist Philipp"
    XCTAssertEqual(resolve(text), text)
}

func testRestartResolutionIsIdempotent() {
    let first = SelfCorrectionResolver.resolve(
        "Hallo mein Name ist Peter, Hallo mein Name ist Philipp",
        locale: .de
    )
    let second = SelfCorrectionResolver.resolve(first.text, locale: .de)

    XCTAssertEqual(second.text, first.text)
    XCTAssertEqual(second.resolvedCount, 0)
    XCTAssertTrue(second.edits.isEmpty)
}
```

- [ ] **Step 3: Markerlose Tests rot ausführen**

Run:

```bash
swift test --filter 'StasiTests.SelfCorrectionResolverTests'
```

Expected: die neuen markerlosen Positivtests schlagen fehl; alle bisherigen Tests bleiben grün.

- [ ] **Step 4: Kandidatentypen und Schutzmengen ergänzen**

Ergänze:

```swift
private struct RestartCandidate {
    let removal: Removal
    let sharedPrefixWords: Int
    let tokenDistance: Int
}

private static let repeatAnnouncementsDE: Set<String> = [
    "wiederhole", "wiederholen", "wiederholt", "erneut", "nochmal", "zitat",
]
private static let repeatAnnouncementsEN: Set<String> = [
    "repeat", "repeating", "again", "quote",
]
private static let restartConnectors: Set<String> = [
    "und", "oder", "and", "or",
]
private static let incompletePrefixWordsDE: Set<String> = [
    "ist", "sind", "war", "wird", "bin", "bist", "am", "um", "an", "mit",
    "für", "zu", "ein", "eine", "der", "die", "das",
]
private static let incompletePrefixWordsEN: Set<String> = [
    "is", "are", "was", "will", "am", "to", "at", "on", "with", "for",
    "a", "an", "the", "my",
]
private static let quoteCharacters: Set<Character> = [
    "\"", "„", "“", "«", "»", "‘", "’",
]
```

- [ ] **Step 5: `resolve` auf zwei Pässe erweitern**

Ersetze den Rückgabeteil von `resolve`:

```swift
let explicit = resolveExplicitCorrections(in: input, locale: locale)
let markerless = resolveMarkerlessRestarts(in: explicit.text, locale: locale)
let edits = explicit.edits + markerless.edits
return Result(
    text: markerless.text,
    resolvedCount: edits.count,
    edits: edits
)
```

- [ ] **Step 6: Begrenzte Kandidatensuche implementieren**

Ergänze die folgenden Helfer. Sie suchen nur innerhalb eines Satzes, höchstens 16 Wörter voraus und höchstens 32 Kandidaten pro Satz:

```swift
private static func resolveMarkerlessRestarts(
    in input: String,
    locale: PolishLocale
) -> PassResult {
    var candidates: [RestartCandidate] = []

    for sentence in sentences(in: input) where !sentence.endsWithQuestion {
        let tokens = tokenize(input, in: sentence.range)
        guard tokens.count >= minimumRepeatedPrefixWords * 2 else { continue }
        candidates.append(contentsOf: markerlessCandidates(
            tokens: tokens,
            sentence: sentence,
            in: input,
            locale: locale
        ))
    }

    return applying(selectNonOverlapping(candidates), to: input)
}

private static func markerlessCandidates(
    tokens: [Token],
    sentence: Sentence,
    in input: String,
    locale: PolishLocale
) -> [RestartCandidate] {
    var result: [RestartCandidate] = []

    for leftStart in tokens.indices {
        guard startsAtClauseBoundary(tokens[leftStart], sentence: sentence, in: input) else {
            continue
        }

        let firstRight = leftStart + minimumRepeatedPrefixWords
        guard firstRight < tokens.count else { continue }
        let lastRight = min(tokens.count - 1, leftStart + maximumRestartWindowWords)

        for rightStart in firstRight...lastRight {
            if result.count >= maximumRestartCandidatesPerSentence { return result }
            if restartConnectors.contains(tokens[rightStart - 1].normalized) { continue }

            let prefix = commonPrefixLength(
                tokens: tokens,
                leftStart: leftStart,
                leftLimit: rightStart,
                rightStart: rightStart,
                rightLimit: tokens.count
            )
            guard prefix >= minimumRepeatedPrefixWords else { continue }
            guard rightStart + prefix < tokens.count else { continue }

            let leftWords = rightStart - leftStart
            if prefix == leftWords {
                guard looksIncompleteExactPrefix(
                    lastToken: tokens[rightStart - 1].normalized,
                    locale: locale
                ) else { continue }
            }

            let rawLower = tokens[leftStart].range.lowerBound
            let rawUpper = tokens[rightStart + prefix].range.upperBound
            guard !containsQuoteBoundary(from: rawLower, to: rawUpper, in: input) else {
                continue
            }
            guard !containsRepeatAnnouncement(
                tokens: tokens,
                range: leftStart..<rightStart,
                locale: locale
            ) else { continue }

            let keptLength = min(
                tokens.count - rightStart,
                max(leftWords, prefix + 1)
            )
            let removal = Removal(
                range: tokens[leftStart].range.lowerBound..<tokens[rightStart].range.lowerBound,
                edit: Edit(
                    removed: phrase(tokens: tokens, range: leftStart..<rightStart, in: input),
                    kept: phrase(
                        tokens: tokens,
                        range: rightStart..<(rightStart + keptLength),
                        in: input
                    )
                )
            )
            result.append(RestartCandidate(
                removal: removal,
                sharedPrefixWords: prefix,
                tokenDistance: rightStart - leftStart
            ))
        }
    }

    return result
}

private static func commonPrefixLength(
    tokens: [Token],
    leftStart: Int,
    leftLimit: Int,
    rightStart: Int,
    rightLimit: Int
) -> Int {
    let maximum = min(
        maximumRepeatedPrefixWords,
        leftLimit - leftStart,
        rightLimit - rightStart
    )
    var length = 0
    while length < maximum,
          tokens[leftStart + length].normalized
            == tokens[rightStart + length].normalized {
        length += 1
    }
    return length
}
```

- [ ] **Step 7: Klausel-, Zitat-, Ankündigungs- und Vollständigkeitsschutz implementieren**

Ergänze:

```swift
private static func startsAtClauseBoundary(
    _ token: Token,
    sentence: Sentence,
    in input: String
) -> Bool {
    var cursor = token.range.lowerBound
    while cursor > sentence.range.lowerBound {
        let previous = input.index(before: cursor)
        let character = input[previous]
        if character.isWhitespace || quoteCharacters.contains(character) {
            cursor = previous
            continue
        }
        return character == "," || character == ";" || character == ":"
            || character == "—" || character == "–"
    }
    return true
}

private static func containsQuoteBoundary(
    from lower: String.Index,
    to upper: String.Index,
    in input: String
) -> Bool {
    input[lower..<upper].contains { quoteCharacters.contains($0) }
}

private static func containsRepeatAnnouncement(
    tokens: [Token],
    range: Range<Int>,
    locale: PolishLocale
) -> Bool {
    let announcements = locale == .de ? repeatAnnouncementsDE : repeatAnnouncementsEN
    return tokens[range].contains { announcements.contains($0.normalized) }
}

private static func looksIncompleteExactPrefix(
    lastToken: String,
    locale: PolishLocale
) -> Bool {
    let words = locale == .de ? incompletePrefixWordsDE : incompletePrefixWordsEN
    return words.contains(lastToken)
}

private static func selectNonOverlapping(
    _ candidates: [RestartCandidate]
) -> [Removal] {
    let ranked = candidates.sorted {
        if $0.sharedPrefixWords != $1.sharedPrefixWords {
            return $0.sharedPrefixWords > $1.sharedPrefixWords
        }
        if $0.tokenDistance != $1.tokenDistance {
            return $0.tokenDistance < $1.tokenDistance
        }
        return $0.removal.range.lowerBound < $1.removal.range.lowerBound
    }

    var selected: [Removal] = []
    for candidate in ranked {
        let overlaps = selected.contains {
            $0.range.lowerBound < candidate.removal.range.upperBound
                && candidate.removal.range.lowerBound < $0.range.upperBound
        }
        if !overlaps { selected.append(candidate.removal) }
    }
    return selected.sorted { $0.range.lowerBound < $1.range.lowerBound }
}
```

- [ ] **Step 8: Resolver-Tests ausführen**

Run:

```bash
swift test --filter 'StasiTests.SelfCorrectionResolverTests'
```

Expected: alle Positiv-, Negativ-, Ketten-, Fenster- und Idempotenztests bestehen.

- [ ] **Step 9: Commit erstellen**

```bash
git add Sources/Stasi/Core/SelfCorrectionResolver.swift \
  Tests/StasiTests/SelfCorrectionResolverTests.swift
git commit -m $'feat(polish): bereinige wiederholte Satzanfänge\n\nCo-Authored-By: Claude <noreply@anthropic.com>'
```

---

### Task 3: Polisher-Summary und AUS-Modus absichern

**Files:**
- Test: `Tests/StasiTests/TranscriptPolisherTests.swift:9-211`

**Interfaces:**
- Consumes: unverändertes `TranscriptPolisher.polishSync(_:locale:entries:level:) -> PolishOutcome`
- Produces: Regressionsschutz für STANDARD, AUS, `.selfCorrection`, Badge und Idempotenz

- [ ] **Step 1: Polisher-Tests ergänzen**

```swift
func testStandardCleansMarkerlessRestartAndRecordsSelfCorrection() {
    let outcome = TranscriptPolisher.polishSync(
        "Hallo, mein Name ist Peter, Hallo, mein Name ist Philipp",
        locale: Locale(identifier: "de_DE"),
        entries: [],
        level: .standard
    )

    XCTAssertEqual(outcome.text, "Hallo, mein Name ist Philipp")
    XCTAssertEqual(outcome.summary.selfCorrectionsResolved, 1)
    XCTAssertEqual(outcome.summary.changes.filter { $0.kind == .selfCorrection }, [
        PolishChange(
            kind: .selfCorrection,
            count: 1,
            removed: "Hallo mein Name ist Peter",
            kept: "Hallo mein Name ist Philipp"
        ),
    ])
    XCTAssertEqual(outcome.summary.badgeText(), "POLIERT · VERSPRECHER")
}

func testOffPreservesMarkerlessRestart() {
    let raw = "Hallo, mein Name ist Peter, Hallo, mein Name ist Philipp"
    let outcome = TranscriptPolisher.polishSync(
        raw,
        locale: Locale(identifier: "de_DE"),
        entries: [],
        level: .off
    )

    XCTAssertEqual(outcome.text, raw)
    XCTAssertEqual(outcome.summary.level, .off)
    XCTAssertFalse(outcome.summary.changedAnything)
}

func testRestartPolishingIsIdempotent() {
    let first = TranscriptPolisher.polishSync(
        "Hallo, mein Name ist Peter, Hallo, mein Name ist Philipp",
        locale: Locale(identifier: "de_DE"),
        entries: [],
        level: .standard
    )
    let second = TranscriptPolisher.polishSync(
        first.text,
        locale: Locale(identifier: "de_DE"),
        entries: [],
        level: .standard
    )

    XCTAssertEqual(second.text, first.text)
    XCTAssertEqual(second.summary.selfCorrectionsResolved, 0)
}
```

- [ ] **Step 2: Polisher-Tests ausführen**

```bash
swift test --filter 'StasiTests.TranscriptPolisherTests'
```

Expected: alle Tests bestehen. Falls `PolishChange`-Details abweichen, die Produktionslogik korrigieren; nicht die erwarteten Sicherheitswerte lockern.

- [ ] **Step 3: Gemeinsamen Resolver-/Polisher-Lauf ausführen**

```bash
swift test --filter 'StasiTests.(SelfCorrectionResolverTests|TranscriptPolisherTests)'
```

Expected: beide Testklassen bestehen gemeinsam.

- [ ] **Step 4: Commit erstellen**

```bash
git add Tests/StasiTests/TranscriptPolisherTests.swift
git commit -m $'test(polish): sichere Neustart-Summary ab\n\nCo-Authored-By: Claude <noreply@anthropic.com>'
```

---

### Task 4: Rohtext, Verlauf, Zwischenablage und Injector Ende-zu-Ende prüfen

**Files:**
- Test: `Tests/StasiTests/DictationSessionTests.swift:705-904`

**Interfaces:**
- Consumes: vorhandene `makeApp`, `makeTargetApplication`, `FakeSpeechEngine`, `FakeHistoryStore`, `TextInjectorSpy`, `ClipboardSpy`
- Produces: Ende-zu-Ende-Vertrag, dass `rawText` vollständig bleibt und alle Ausgabekanäle denselben bereinigten Text erhalten

- [ ] **Step 1: Erfolgreichen Ausgabepfad testen**

Füge bei den bestehenden Injection-Tests ein:

```swift
func testRestartCleanupKeepsRawTextAndInjectsPolishedText() async {
    let target = makeTargetApplication(named: "Notizen")
    let raw = "Hallo, mein Name ist Peter, Hallo, mein Name ist Philipp"
    let polished = "Hallo, mein Name ist Philipp"
    let audio = FakeAudioCapture()
    let history = FakeHistoryStore()
    let injector = TextInjectorSpy()
    let clipboard = ClipboardSpy()
    let app = makeApp(
        audio: audio,
        engines: [FakeSpeechEngine(text: raw)],
        history: history,
        frontmostApplication: { target },
        isTextFieldEditable: { true },
        injectText: { text, pid in injector.inject(text, targetPID: pid) },
        copyToClipboard: { clipboard.copy($0) }
    )
    app.settings.language = "de_DE"
    app.settings.postProcessing = .standard

    app.startDictation()
    await waitUntil { audio.isRunning && app.partialText == raw }
    app.stopDictation()
    await waitUntil { app.phase == .idle }

    XCTAssertEqual(history.records.first?.rawText, raw)
    XCTAssertEqual(history.records.first?.correctedText, polished)
    XCTAssertEqual(history.records.first?.polish?.selfCorrectionsResolved, 1)
    XCTAssertEqual(clipboard.strings, [polished])
    XCTAssertEqual(injector.texts, [polished])
    XCTAssertEqual(injector.targetPIDs, [target.processIdentifier])
}
```

- [ ] **Step 2: Injection-Fehler testen**

```swift
func testRestartCleanupSurvivesInjectionFailure() async {
    let target = makeTargetApplication(named: "Notizen")
    let raw = "Hallo, mein Name ist Peter, Hallo, mein Name ist Philipp"
    let polished = "Hallo, mein Name ist Philipp"
    let audio = FakeAudioCapture()
    let history = FakeHistoryStore()
    let injector = TextInjectorSpy()
    injector.succeeds = false
    let clipboard = ClipboardSpy()
    let app = makeApp(
        audio: audio,
        engines: [FakeSpeechEngine(text: raw)],
        history: history,
        frontmostApplication: { target },
        isTextFieldEditable: { true },
        injectText: { text, pid in injector.inject(text, targetPID: pid) },
        copyToClipboard: { clipboard.copy($0) }
    )
    app.settings.language = "de_DE"
    app.settings.postProcessing = .standard

    app.startDictation()
    await waitUntil { audio.isRunning && app.partialText == raw }
    app.stopDictation()
    await waitUntil { app.phase == .idle }

    XCTAssertEqual(history.records.first?.rawText, raw)
    XCTAssertEqual(history.records.first?.correctedText, polished)
    XCTAssertEqual(clipboard.strings, [polished])
    XCTAssertEqual(injector.texts, [polished])
}
```

- [ ] **Step 3: Die beiden Tests ausführen**

```bash
swift test --filter 'StasiTests.DictationSessionTests/testRestartCleanupKeepsRawTextAndInjectsPolishedText'
swift test --filter 'StasiTests.DictationSessionTests/testRestartCleanupSurvivesInjectionFailure'
```

Expected: beide Tests bestehen.

- [ ] **Step 4: Vollständige Testsuite verbindlich ausführen**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
```

Expected: Exitcode 0 und keine fehlgeschlagenen Tests.

Zusätzlich auf einer lokalen Umgebung, in der der Swift-Test-Runner nicht hängt:

```bash
swift test
```

Expected: Exitcode 0.

- [ ] **Step 5: Commit erstellen**

```bash
git add Tests/StasiTests/DictationSessionTests.swift
git commit -m $'test(session): sichere Rohtext bei Neustarts\n\nCo-Authored-By: Claude <noreply@anthropic.com>'
```

---

### Task 5: Textbereinigungs-Paket final prüfen

**Files:**
- Verify only: `Sources/Stasi/Core/SelfCorrectionResolver.swift`
- Verify only: `Tests/StasiTests/SelfCorrectionResolverTests.swift`
- Verify only: `Tests/StasiTests/TranscriptPolisherTests.swift`
- Verify only: `Tests/StasiTests/DictationSessionTests.swift`

**Interfaces:**
- Consumes: Tasks 1–4
- Produces: geprüfter Feature-Branch für den Release-Vorbereitungsplan

- [ ] **Step 1: Diff und verbotene Nebenänderungen prüfen**

```bash
git status --short
git diff main...HEAD -- Sources/Stasi/Core/SelfCorrectionResolver.swift \
  Tests/StasiTests/SelfCorrectionResolverTests.swift \
  Tests/StasiTests/TranscriptPolisherTests.swift \
  Tests/StasiTests/DictationSessionTests.swift
git diff --check main...HEAD
```

Expected: nur die geplanten Resolver- und Teständerungen; keine UI-, Schema- oder Modelldienst-Änderung.

- [ ] **Step 2: Vollständige Tests erneut ausführen**

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
```

Expected: Exitcode 0.

- [ ] **Step 3: Review anfordern**

Nutze `superpowers:requesting-code-review` für den Diff dieses Plans. Findings werden vor dem Release-Vorbereitungsplan behoben und erneut getestet.
