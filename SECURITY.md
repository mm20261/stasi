# Sicherheitsrichtlinie

## Sicherheitslücken melden

Bitte Sicherheitslücken nicht in einem öffentlichen Issue veröffentlichen. Verwende
stattdessen GitHubs [private Vulnerability-Reporting-Funktion](https://github.com/mm20261/stasi/security/advisories/new),
damit Details vertraulich geprüft und koordiniert behoben werden können. Beschreibe
Auswirkung, betroffene Version, Reproduktionsschritte und – wenn möglich – einen
minimalen Nachweis. Vertrauliche Diktate, Zugangsdaten und personenbezogene Daten
gehören nicht in den Bericht.

## Datenfluss und Netzwerkzugriff

Transkription, Nachbearbeitung, Wörterbuch, Verlauf und Audioverarbeitung laufen
lokal auf dem Mac. Der einzige Netzwerkzugriff der App ist ein Abruf der
GitHub-Releases-API. Er erfolgt ausschließlich, wenn der Nutzer in
**Einstellungen → ÜBER** die Update-Prüfung anklickt. Die App überträgt dabei keine
Diktate oder Audiodaten.

Stasi ist bewusst nicht sandboxed. Der globale Hotkey wird über einen `CGEventTap`
erkannt, und Text wird über synthetische Tastaturereignisse in die fokussierte App
eingefügt. Diese Kernfunktionen sind mit der App Sandbox nicht umsetzbar. Mikrofon,
Spracherkennung und Bedienungshilfen bleiben durch die jeweiligen macOS-TCC-
Zustimmungen geschützt.
