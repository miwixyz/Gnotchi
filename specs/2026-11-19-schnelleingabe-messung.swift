import Foundation
// Referenz: Do 19.11.2026 10:00 lokale Zeit
var c = DateComponents(); c.year=2026; c.month=11; c.day=19; c.hour=10
let ref = Calendar.current.date(from: c)!
let cases: [(String,String)] = [
 ("Zahnarzt Do 15 Uhr","2026-11-26 15:00"),
 ("Zahnarzt morgen um 15 Uhr","2026-11-20 15:00"),
 ("Call mit Andrea übermorgen 9:30","2026-11-21 09:30"),
 ("Meeting am 3.12. um 14 Uhr","2026-12-03 14:00"),
 ("Meeting am 3. Dezember 14:00","2026-12-03 14:00"),
 ("Kino BiiGZ Freitag 20 Uhr","2026-11-20 20:00"),
 ("nächsten Montag Steuerberater 11 Uhr","2026-11-23 11:00"),
 ("heute 18 Uhr Sport","2026-11-19 18:00"),
 ("Müll rausbringen morgen früh","2026-11-20 (früh)"),
 ("Rechnung zahlen bis 30.11.","2026-11-30"),
 ("in 2 Stunden Cati anrufen","2026-11-19 12:00"),
 ("in 3 Tagen Paket abholen","2026-11-22"),
 ("Mittwoch halb drei Friseur","2026-11-25 14:30"),
 ("Geburtstag Mama 12.01.2027","2027-01-12"),
 ("Weihnachtsfeier 18.12. 19:00","2026-12-18 19:00"),
 ("Termin Dienstag 8 Uhr","2026-11-24 08:00"),
 ("Flug am Sonntag um 7:15","2026-11-22 07:15"),
 ("Teams-Call 16:30","2026-11-19 16:30"),
 ("nächste Woche Mittwoch Vertrag prüfen","2026-11-25"),
 ("am Wochenende Fahrrad reparieren","2026-11-21"),
]
let det = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
let f = DateFormatter(); f.dateFormat="yyyy-MM-dd HH:mm EEE"; f.locale=Locale(identifier:"de_DE")
for (s,exp) in cases {
  let ms = det.matches(in: s, options: [], range: NSRange(s.startIndex..., in: s))
  // NSDataDetector hat keinen öffentlichen Referenzdatum-Parameter → relative Angaben gegen "jetzt"
  let got = ms.map { m in "\(f.string(from: m.date!)) [\((s as NSString).substring(with: m.range))]" }.joined(separator:" | ")
  print("\(s)\n   erwartet \(exp)\n   erkannt  \(got.isEmpty ? "—" : got)")
}
