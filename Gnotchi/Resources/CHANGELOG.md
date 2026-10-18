# Changelog

Alle nennenswerten Änderungen an Gnotchi.

## [Unreleased]

### Neu

- Eigenes Repo, ausgelagert aus Seam (Zweig `feature/notch-medien`): Gnotchi hat keine
  Bedienungshilfen-Freigabe, der Perl-Kindprozess des Medien-Adapters kann sie also nicht erben.
- Datenquelle für die Mediensteuerung: eingespielter `mediaremote-adapter`, gestartet über
  `/usr/bin/perl` nur aus einem unveränderten, von Michaels Team signierten Bundle; Strom
  zeilenweise mit Längenlimit, Titel bereinigt, Cover begrenzt dekodiert.
- Menüleisten-App mit Einstellungen („Musik in der Notch“, „Bei Anmeldung starten“), Hilfe,
  Update-Suche (Sparkle). Die Insel selbst folgt.

### Geändert

- Fortschritt in der großen Insel: dünner Balken wie im Kontrollzentrum statt Regler mit festem
  Knopf. Der Knopf erscheint nur beim Überfahren oder Ziehen; Klicken oder Ziehen spult, gesendet
  wird erst beim Loslassen. Ohne Dauer (Livestream) bleibt der Balken leer und gesperrt.
- Welche App spielt: Die große Insel zeigt über dem Titel Symbol und Namen der Quell-App
  (z. B. „Spotify“, „Safari“, „Musik“), die kleine ein winziges App-Abzeichen am Cover. Der Name
  kommt aus der installierten App, nie von der Website. Das Symbol oben rechts entfällt.
- Wo die Musik spielt: Läuft sie auf einem anderen Gerät (z. B. Spotify Connect auf externe
  Lautsprecher), zeigt die große Insel oben rechts „Auf anderem Gerät“, bei AirPlay oder Bluetooth
  den Namen des Geräts. Klein ersetzt dann ein Lautsprecher den Pegel (bei anderem Gerät und
  AirPlay). Gnotchi fragt dafür nur ab, ob eine App gerade Ton ausgibt – es hört nichts mit.
- Einstellung „Aufklappen nach“ (Sofort, 0,3 s, 0,6 s, 1 s; ab Werk 0,6 s): Die Insel geht erst
  auf, wenn die Maus so lange darüber bleibt – flüchtiges Überfahren löst nichts mehr aus.
- Nur eine Notch-App: Zeichnet eine andere App ebenfalls über die Notch (z. B. NotchNook), zeigt
  Gnotchi oben im Menü und in den Einstellungen einen Hinweis mit ihrem Namen.
