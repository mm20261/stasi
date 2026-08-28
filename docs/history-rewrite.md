# Git-Autorenhistorie sicher umschreiben

Diese Checkliste bereitet eine **spätere, separat freizugebende** Umschreibung von Autoren- und E-Mail-Daten vor. Sie führt jetzt nichts aus. Vor der späteren Ausführung müssen `OLD_EMAIL`, `NEW_NOREPLY_EMAIL` und `NEW_NAME` interaktiv bestätigt werden; weder echte private Daten noch erfundene Ersatzwerte gehören in dieses Dokument.

## 1. Entscheidung und Schreibstopp

- [ ] Alle Reparaturcommits, finalen Tests und der manuelle Smoke-Test sind erfolgreich abgeschlossen.
- [ ] Der Arbeitsbaum ist sauber: `git status --short` liefert keine Ausgabe.
- [ ] Verantwortliche Person, Wartungsfenster und **exakter Umfang** sind bestätigt: welche Branches, Tags und sonstigen Refs umgeschrieben werden sollen.
- [ ] `OLD_EMAIL`, `NEW_NOREPLY_EMAIL` und `NEW_NAME` werden interaktiv eingegeben, geprüft und nochmals bestätigt.
- [ ] Für `NEW_NOREPLY_EMAIL` ist entschieden, ob die bestätigte GitHub-Noreply-Adresse des Zielkontos verwendet wird; die Adresse wird in den GitHub-E-Mail-Einstellungen verifiziert.
- [ ] Alle Mitwirkenden haben Schreibstopp zugesagt; während Analyse, Rewrite und Prüfung entstehen keine neuen Commits, Tags oder Branches.
- [ ] Alle Beteiligten bestätigen ausdrücklich: **Jeder tatsächlich umgeschriebene Commit und alle seine Nachfahren erhalten neue IDs.** Historien ohne Verbindung zu einem betroffenen Commit können unveränderte IDs behalten. Offene Pull Requests, Forks und vorhandene Klone müssen koordiniert, neu basiert oder frisch geklont werden.
- [ ] Branch- und Tag-Schutzregeln sowie die erforderlichen GitHub-Berechtigungen sind inventarisiert. Eine Änderung dieser Regeln ist noch nicht freigegeben.

## 2. Externe Sicherung und Inventar

- [ ] Außerhalb des Arbeits-Repositorys und auf einem unabhängigen Speicherort wird ein vollständiges Repository-Backup als verifizierter Mirror-Klon erstellt. Ein normaler Klon genügt nicht. Falls kein Mirror-Klon verwendet wird, muss eine ausdrücklich geprüfte Fetch-Refspec alle gewünschten Refs abdecken, zum Beispiel `+refs/*:refs/*`.
- [ ] Für den Backup-Klon werden Fetch-Refspec und tatsächlich vorhandene Refs geprüft; ein frischer Test-Klon daraus sowie `git fsck --full` müssen erfolgreich sein.
- [ ] Vorher werden alle lokalen und vom Remote angebotenen Refs, Branches, Tags, Remotes und Objekt-IDs in einem Protokoll **außerhalb des Repositorys** gesichert:

  ```bash
  git show-ref --head
  git branch --all --verbose --no-abbrev
  git tag --list --format='%(refname) %(objectname) %(objecttype)'
  git remote --verbose
  git remote show origin
  git config --get-all remote.origin.fetch
  git ls-remote --refs origin
  ```

- [ ] GitHub-verwaltete Pull-Request-Refs werden separat inventarisiert und koordiniert. Sie sind serverkontrolliert und dürfen nicht als normal wiederherstellbare oder frei pushbare Backup-Refs eingeplant werden.
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

- [ ] **Mailmap-Grenze:** `--mailmap` ändert Autoren-, Committer- und Tagger-Metadaten, aber keine frei formulierten Commit-Nachrichten, Trailer oder annotierten Tag-Nachrichten. Deshalb werden diese Inhalte in der trockenen Analyse separat auf den exakt bestätigten Wert geprüft:

  ```bash
  git log --all --format='%H%x00%B%x00' | grep -aF -- "$OLD_EMAIL" || true
  git for-each-ref refs/tags \
    --format='%(objecttype)%00%(refname)%00%(contents)%00' \
    | grep -aF -- "$OLD_EMAIL" || true
  ```

  Jeder Treffer wird mit Objekt-ID und Ref protokolliert. Ein Treffer erfordert eine **separat geprüfte, eng begrenzte Regel für Nachrichteninhalte** (zum Beispiel einen später zu reviewenden Message-Callback). Diese Anleitung erfindet oder führt keinen solchen Callback aus. Ohne diese Zusatzentscheidung darf später nicht behauptet werden, `OLD_EMAIL` sei nirgends mehr vorhanden.

- [ ] Annotierte Tags und sonstige Refs werden ausdrücklich in die Analyse einbezogen; nicht nur der aktuelle Branch wird geprüft.
- [ ] Signierte Commits werden vor dem Rewrite über alle vorgesehenen Refs inventarisiert; Status, Fingerprint und Signer werden außerhalb des Repositorys protokolliert:

  ```bash
  git log --all --format='%H%x09%G?%x09%GF%x09%GS'
  ```

  `G`, `U`, `B`, `X`, `Y`, `R` und `E` in `%G?` markieren vorhandene bzw. geprüfte Signaturzustände; `N` bedeutet keine Signatur. Das Inventar wird nicht als Zusage missverstanden, die Signaturen blieben erhalten.

## 4. Mailmap und geplanter Befehl

- [ ] Erst nach interaktiver Bestätigung wird außerhalb des Repositorys eine temporäre Mailmap mit genau dieser **Platzhalterform** angelegt:

  ```text
  NEW_NAME <NEW_NOREPLY_EMAIL> <OLD_EMAIL>
  ```

- [ ] Die Datei enthält ausschließlich bestätigte Werte und wird weder committed noch als `.mailmap` im Repository angelegt.
- [ ] `git-filter-repo` verarbeitet nur die Refs, die im Rewrite-Klon vorhanden und für den Lauf erreichbar sind. Deshalb werden Mirror-/Fetch-Abdeckung und das Ref-Inventar vor dem Test-Rewrite miteinander verglichen.
- [ ] Eine Einschränkung mit `--refs` ändert das Verhalten zu einem partiellen Rewrite und kann alte und neue Historie nebeneinander belassen. Jede solche Einschränkung benötigt eine separate Prüfung und Freigabe; sie wird nicht stillschweigend ergänzt.
- [ ] Der spätere Rewrite wird zuerst in einem frischen Test-Klon mit der dokumentierten `git-filter-repo`-Version erprobt. Die geplante Befehlsform ohne ungeprüfte Ref-Einschränkung lautet:

  ```bash
  git filter-repo --mailmap /ABSOLUTE/PATH/TO/CONFIRMED-MAILMAP
  ```

- [ ] Vor Ausführung werden Zielklon, Mailmap-Inhalt, Scope, vorhandene Refs und Backup ein letztes Mal von einer zweiten Person geprüft.
- [ ] Vor Ausführung liegt eine eigene ausdrückliche Freigabe für die Signaturfolgen vor: Sobald ein signierter Commit selbst oder einer seiner Eltern umgeschrieben wird, entsteht für ihn beziehungsweise seine betroffenen Nachfahren ein neues Commit-Objekt. Die ursprüngliche kryptografische Signatur und GitHubs Status „Verified“ gelten für das neue Objekt nicht weiter.
- [ ] Für alle betroffenen signierten Commits existiert vorab ein **separat reviewter Plan zur bewussten Neuerstellung und Neusignierung**. Dieser legt Identität, Schlüsselzugriff, Commit-Reihenfolge, Merge-Behandlung und anschließende Verifikation fest. Ohne diesen Plan und die ausdrückliche Freigabe wird nicht umgeschrieben. Diese Anleitung erzeugt oder signiert keine Commits.
- [ ] Dieser Befehl wird **nicht** im Rahmen dieser Anleitung ausgeführt.

## 5. Prüfung nach einem später genehmigten Test-Rewrite

- [ ] Alle vorgesehenen Branches, Tags und sonstigen Refs sind vorhanden und zeigen auf die erwartete umgeschriebene Historie.
- [ ] Autoren-, Committer- und Tagger-Metadaten werden über alle Refs auf `OLD_EMAIL` geprüft.
- [ ] Commit-Nachrichten einschließlich Trailer und Inhalte annotierter Tags werden erneut separat geprüft:

  ```bash
  git log --all --format='%H%x00%B%x00' | grep -aF -- "$OLD_EMAIL" || true
  git for-each-ref refs/tags \
    --format='%(objecttype)%00%(refname)%00%(contents)%00' \
    | grep -aF -- "$OLD_EMAIL" || true
  ```

  Nur wenn Metadaten **und** diese Inhaltsprüfungen ohne Fund sind, darf für den geprüften Ref-Umfang festgehalten werden, dass `OLD_EMAIL` nicht mehr vorkommt. Treffer werden nicht durch die Mailmap schöngeredet; sie blockieren die Veröffentlichung bis zur separat freigegebenen Inhaltsregel.

- [ ] Das Vorher-/Nachher-Inventar signierter Commits wird Objekt für Objekt abgeglichen. Für neu erzeugte Commits wird GitHub „Verified“ nicht erwartet, solange der separat freigegebene Neusignierungsplan nicht vollständig ausgeführt und kryptografisch verifiziert wurde.
- [ ] Commit-Anzahl, Topologie, Merge-Struktur, Dateiinhalte und Tag-Ziele werden gegen das Vorher-Inventar abgeglichen.
- [ ] Lightweight Tags werden als direkte Refs auf ihre erwarteten neuen Commit-Ziele geprüft; sie besitzen weder eigenes Tagger-Feld noch eigene Signatur.
- [ ] Annotierte Tags besitzen ein eigenes Tag-Objekt samt Tagger-Daten und werden deshalb getrennt geprüft. Wird ein signiertes annotiertes Tag umgeschrieben, ist seine bisherige Signatur nicht mehr gültig; seine bewusste Neuerstellung und Neusignierung muss separat geplant und freigegeben werden.
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
