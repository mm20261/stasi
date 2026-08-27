# Git-Autorenhistorie sicher umschreiben

Diese Checkliste bereitet eine **spätere, separat freizugebende** Umschreibung von Autoren- und E-Mail-Daten vor. Sie führt jetzt nichts aus. Vor der späteren Ausführung müssen `OLD_EMAIL`, `NEW_NOREPLY_EMAIL` und `NEW_NAME` interaktiv bestätigt werden; weder echte private Daten noch erfundene Ersatzwerte gehören in dieses Dokument.

## 1. Entscheidung und Schreibstopp

- [ ] Alle Reparaturcommits, finalen Tests und der manuelle Smoke-Test sind erfolgreich abgeschlossen.
- [ ] Der Arbeitsbaum ist sauber: `git status --short` liefert keine Ausgabe.
- [ ] Verantwortliche Person, Wartungsfenster und **exakter Umfang** sind bestätigt: welche Branches, Tags und sonstigen Refs umgeschrieben werden sollen.
- [ ] `OLD_EMAIL`, `NEW_NOREPLY_EMAIL` und `NEW_NAME` werden interaktiv eingegeben, geprüft und nochmals bestätigt.
- [ ] Für `NEW_NOREPLY_EMAIL` ist entschieden, ob die bestätigte GitHub-Noreply-Adresse des Zielkontos verwendet wird; die Adresse wird in den GitHub-E-Mail-Einstellungen verifiziert.
- [ ] Alle Mitwirkenden haben Schreibstopp zugesagt; während Analyse, Rewrite und Prüfung entstehen keine neuen Commits, Tags oder Branches.
- [ ] Alle Beteiligten bestätigen ausdrücklich: **Alle Commit-IDs im umgeschriebenen Scope ändern sich.** Offene Pull Requests, Forks und vorhandene Klone müssen koordiniert, neu basiert oder frisch geklont werden.
- [ ] Branch- und Tag-Schutzregeln sowie die erforderlichen GitHub-Berechtigungen sind inventarisiert. Eine Änderung dieser Regeln ist noch nicht freigegeben.

## 2. Externe Sicherung und Inventar

- [ ] Außerhalb des Arbeits-Repositorys und auf einem unabhängigen Speicherort wird ein vollständiges Repository-Backup erstellt, zum Beispiel als Mirror-Klon.
- [ ] Das Backup wird durch einen frischen Test-Klon und `git fsck --full` geprüft.
- [ ] Vorher werden alle lokalen und Remote-Refs, Branches, Tags, Remotes und Objekt-IDs in einem Protokoll **außerhalb des Repositorys** gesichert:

  ```bash
  git show-ref --head
  git branch --all --verbose --no-abbrev
  git tag --list --format='%(refname) %(objectname) %(objecttype)'
  git remote --verbose
  git remote show origin
  ```

- [ ] Die Wiederherstellung aus dem externen Backup wurde verstanden. Reflogs allein sind **kein** ausreichender Rollback-Plan.

## 3. Werkzeug und trockene Analyse

- [ ] `git-filter-repo` stammt aus einer vertrauenswürdigen Quelle, ist installiert und wird vorab verifiziert:

  ```bash
  git filter-repo --version
  ```

- [ ] Die Analyse findet in einem frischen, entbehrlichen Klon des vollständigen Repositorys statt, nicht im einzigen Arbeitsklon.
- [ ] Der alte Wert wird zunächst nur gesucht; Fundstellen und betroffene Refs werden mit dem festgelegten Umfang abgeglichen:

  ```bash
  git log --all --format='%H%x09%an%x09%ae%x09%cn%x09%ce'
  git for-each-ref --format='%(refname) %(objectname) %(objecttype)'
  git cat-file --batch-check --batch-all-objects
  ```

- [ ] Annotierte Tags und sonstige Refs werden ausdrücklich in die Analyse einbezogen; nicht nur der aktuelle Branch wird geprüft.

## 4. Mailmap und geplanter Befehl

- [ ] Erst nach interaktiver Bestätigung wird außerhalb des Repositorys eine temporäre Mailmap mit genau dieser **Platzhalterform** angelegt:

  ```text
  NEW_NAME <NEW_NOREPLY_EMAIL> <OLD_EMAIL>
  ```

- [ ] Die Datei enthält ausschließlich bestätigte Werte und wird weder committed noch als `.mailmap` im Repository angelegt.
- [ ] Der spätere Rewrite wird zuerst in einem frischen Test-Klon mit der dokumentierten `git-filter-repo`-Version erprobt. Die geplante Befehlsform lautet:

  ```bash
  git filter-repo --mailmap /ABSOLUTE/PATH/TO/CONFIRMED-MAILMAP
  ```

- [ ] Vor Ausführung werden Zielklon, Mailmap-Inhalt, Scope und Backup ein letztes Mal von einer zweiten Person geprüft.
- [ ] Dieser Befehl wird **nicht** im Rahmen dieser Anleitung ausgeführt.

## 5. Prüfung nach einem später genehmigten Test-Rewrite

- [ ] Alle vorgesehenen Branches, Tags und sonstigen Refs sind vorhanden und zeigen auf die erwartete umgeschriebene Historie.
- [ ] Autoren-, Committer- und Tagger-Daten werden über alle Refs geprüft; `OLD_EMAIL` kommt nirgends mehr vor.
- [ ] Commit-Anzahl, Topologie, Merge-Struktur, Dateiinhalte und Tag-Ziele werden gegen das Vorher-Inventar abgeglichen.
- [ ] Annotierte und signierte Tags werden gesondert geprüft; umgeschriebene signierte Objekte benötigen eine bewusst geplante Neusignierung.
- [ ] Anwendung und Release-Artefakte werden vollständig neu gebaut; finale Tests und Smoke-Test laufen erneut erfolgreich.
- [ ] Das Ergebnis wird in einem zweiten frischen Klon geprüft, bevor irgendein Remote geändert wird.

## 6. Veröffentlichung nur mit eigener Freigabe

- [ ] Force-Push ist eine **separate, ausdrückliche Freigabe** nach erfolgreicher Prüfung; diese Anleitung erteilt sie nicht.
- [ ] Vor einer Freigabe sind Remote-Schutzregeln, GitHub-Noreply-Zuordnung, Branch-/Tag-Umfang, Push-Reihenfolge und Kommunikationsplan bestätigt.
- [ ] Mitwirkende wissen, dass alte Klone und Forks die alte Historie erneut einbringen können; die Wiederaufnahme von Schreibzugriff erfolgt erst nach koordinierter Aktualisierung oder frischem Klon.
- [ ] Offene Pull Requests werden einzeln behandelt und nicht stillschweigend durch die neue Historie ersetzt.

## 7. Rollback

- [ ] Bei falschem Scope, fehlenden Refs, unerwarteten Identitäten, fehlerhaften Tags oder roten Tests wird nicht veröffentlicht.
- [ ] Falls bereits veröffentlicht wurde, werden Schreibzugriffe sofort wieder gestoppt und die Refs aus dem verifizierten **externen Vollbackup** nach eigener ausdrücklicher Freigabe wiederhergestellt.
- [ ] Das Vorher-Inventar dient zum Abgleich aller Branches, Tags und sonstigen Refs. Reflogs gelten nur als zusätzliche Diagnosehilfe, nicht als primäre Sicherung.
