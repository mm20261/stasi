# Zu Stasi beitragen

Danke für dein Interesse an Stasi. Beiträge sollten klein, nachvollziehbar und durch
Tests abgesichert sein.

## Voraussetzungen

- macOS 26 oder neuer
- Apple Silicon
- Eine Toolchain mit Unterstützung für Swift 6.2 beziehungsweise Swift Tools 6.2

## Bauen und testen

Eine lokale App entsteht mit:

```bash
./scripts/make-app.sh
open build/Stasi.app
```

Die vollständige Testsuite wird direkt mit `xctest` ausgeführt:

```bash
swift build --build-tests
xcrun xctest "$(swift build --show-bin-path)/StasiPackageTests.xctest"
```

`swift test` kann in der Runner-Infrastruktur hängen. Der direkte Aufruf verwendet
den von SwiftPM ermittelten Binärpfad und ist deshalb der verbindliche Testweg; siehe
auch [README.md](README.md) und das interne [AGENTS.md](AGENTS.md).

Bei Änderungen an Logik gilt TDD: zuerst einen fehlschlagenden Test schreiben oder
anpassen, danach die Implementierung ändern und abschließend die vollständige Suite
ausführen. Die Pipeline-E2E-Tests benötigen TCC-Zustimmungen und bleiben ohne
`STASI_PIPELINE_E2E=1` erwartungsgemäß übersprungen.

## Commit-Nachrichten

Commit-Nachrichten werden auf Deutsch im Conventional-Commits-Stil geschrieben. Der
Betreff soll knapp erklären, was sich ändert. Beispiele aus der Historie:

```text
fix(resources): Stasi-Stasi-Bundle-Fallthrough ohne fatalError
docs(architecture): ergänze geprüfte Runtime-Karte
docs(release): halte Veröffentlichungsstand fest
```

## Diagnose

Das rotierende Laufzeitprotokoll liegt unter:

```text
~/Library/Application Support/Stasi/debug.log
```

Bitte vor dem Teilen prüfen und persönliche Diktatinhalte oder andere vertrauliche
Angaben entfernen. Weitere Schritte stehen in der
[Fehlerbehebung](docs/troubleshooting.md).

## Pull-Request-Ablauf

1. Einen fokussierten Branch mit möglichst kleiner Änderung erstellen.
2. Verhalten und Logik nach der TDD-Regel absichern.
3. Die vollständige Testsuite lokal ausführen.
4. Bei nutzerrelevanten Änderungen `CHANGELOG.md` ergänzen.
5. Im Pull Request Problem, Lösung, Testnachweis und bekannte Grenzen beschreiben.
6. CI und Review abwarten und Rückmeldungen in separaten, nachvollziehbaren Änderungen
   einarbeiten.

`AGENTS.md` ist das interne, sitzungsübergreifende Agent-Gedächtnis. Seine technischen
Sicherheitsregeln gelten für Änderungen am Projekt; sie werden hier bewusst nicht
dupliziert.
