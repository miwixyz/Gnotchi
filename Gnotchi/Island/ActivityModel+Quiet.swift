import Foundation

/// Ruhige Insel (0.16.0, Michael 27.10.): Ohne Hardware-Notch wirkte die schwarze Insel auf der hellen Menüleiste wie
/// ein Fremdkörper, obwohl sie nur Wetter und Ungelesen-Zahlen zeigte. Dann Glas wie die Menüleiste; bei jeder
/// Live-Aktivität wieder schwarz. Ob die Insel ohne Notch läuft und klein ist, prüft `IslandView` (je Bildschirm).
extension ActivityModel {

    /// Steht in der kleinen Insel gerade nur die Ruhe-Anzeige (Wetter, Ablage, Ungelesen)? Dieselben Bedingungen wie
    /// der Zweig `IdleCompact` in `IslandView.rotationCompactActivity`, dazu der Schalter.
    var showsQuietIsland: Bool {
        Self.isQuiet(enabled: quietIsland, idleContent: hasIdleContent,
                     live: [recording != nil, timerAlarm, currentActivity != nil, media.info != nil && media.isVisible,
                            privacy.isActive])
    }

    /// `live`: Aufnahme, Timer-Alarm, rotierende Aktivität, sichtbare Musik, Mikrofon/Kamera – eins davon → schwarz.
    nonisolated static func isQuiet(enabled: Bool, idleContent: Bool, live: [Bool]) -> Bool {
        enabled && idleContent && !live.contains(true)
    }
}
