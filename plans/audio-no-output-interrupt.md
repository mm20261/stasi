# Plan: Musik darf beim Diktieren nicht stocken

## Befund (Ursache)
`AudioCapture` benutzt `AVAudioEngine`. Sobald man `engine.inputNode` anfasst,
baut AVAudioEngine intern eine **I/O-Kette mit Output-Node** auf und öffnet damit
auch das **Ausgabegerät**. Pro Aufnahme wird die Engine neu erzeugt und danach
komplett zerstoert (`stop()` + `reset()` + `nil`). Jedes Start/Stop reisst also
das Default-Output-Device auf/zu -> HAL-Reconfig -> Musik stockt kurz und klingt
danach kaputt (Sample-Rate/Format-Neuverhandlung).

Zusaetzlich: `MicrophoneScanner.apply` setzt
`kAudioOutputUnitProperty_CurrentDevice` auf der AUHAL der Engine, was die
Reconfig verschaerft.

Wispr Flow & Co. machen es anders: **reiner Input-Pfad, Output-Element aus.**

## Ziel
Aufnahme beruehrt das Ausgabegeraet nie. Keine Pause, kein Glitch, kein
Formatwechsel bei laufender Musik.

## Loesung
`AudioCapture` intern von `AVAudioEngine` auf eine **input-only AUHAL**
umstellen (`kAudioUnitSubType_HALOutput`):

1. AudioComponent `kAudioUnitType_Output` / `kAudioUnitSubType_HALOutput` holen.
2. `kAudioOutputUnitProperty_EnableIO`: Element 1 (Input) = 1, **Element 0
   (Output) = 0**. Das ist der entscheidende Schritt.
3. `kAudioOutputUnitProperty_CurrentDevice` auf das Wunsch-Mikro setzen (UID ->
   DeviceID wie bisher via `MicrophoneScanner.deviceID(forTransportUID:)`);
   ohne Wunsch das Default-**Input**-Device explizit setzen.
4. Natives Format vom Geraet lesen (`kAudioUnitProperty_StreamFormat`, Scope
   Output, Element 1). **Nicht** die Geraete-Sample-Rate aendern
   (`kAudioDevicePropertyNominalSampleRate` niemals schreiben) - genau das
   killt fremde Wiedergabe.
5. Client-Format auf Float32 non-interleaved setzen (Scope Output, Element 1).
6. `AURenderCallback` (kAudioOutputUnitProperty_SetInputCallback) ->
   `AudioUnitRender` in einen selbst allozierten `AVAudioPCMBuffer` ->
   danach exakt der bestehende `handle(_:)`-Pfad (Level, Converter, WAV, onBuffer).
7. `stop()`: `AudioOutputUnitStop` + `AudioUnitUninitialize` +
   `AudioComponentInstanceDispose`. Input-only -> Output bleibt unangetastet.

## Harte Regeln
- Puffer-Ownership wie bisher: **niemals** einen geliehenen Puffer weiterreichen
  (war schon mal Heap-Korruption). Immer eigener Puffer / Converter-Ergebnis.
- Nie in globale Audio-Properties schreiben (Default-Device, Sample-Rate,
  Volume). Nur Properties auf der **eigenen** AudioUnit.
- Kein `AVAudioEngine` mehr im Aufnahmepfad. `AVAudioPlayer`/`NSSound` in der UI
  bleiben unveraendert.

## Schnittstelle
`protocol AudioCapturing` und `AudioCapture.EngineHooks` bleiben in ihrer
Semantik erhalten, damit `AppState`/`DictationSession` und die bestehenden Tests
unveraendert weiterlaufen. Hooks duerfen umbenannt/angepasst werden, solange die
Dateilebenszyklus-Tests weiterhin ohne Hardware laufen.

## Tests
- Bestehende Suite (341 Tests) muss gruen bleiben: `swift test`.
- Neu: Format-Aushandlung (nativ != Ziel -> Converter gesetzt), Buffer-Kopie
  ist unabhaengig vom Quellspeicher, `stop()` schliesst die WAV-Datei,
  Start-Fehler raeumt sauber auf.
- Nicht testbar automatisch: das eigentliche Nicht-Stocken. Manuell: Musik
  laufen lassen, 5x diktieren, darf nicht zucken.

## Nicht im Scope
UI, Transkription, Nachbearbeitung.
