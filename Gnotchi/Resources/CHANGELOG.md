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
