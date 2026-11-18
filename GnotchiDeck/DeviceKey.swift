import Foundation

/// Tasten „Ausgabe“ und „Mikrofon“ (0.38): Ausgabe bzw. Mikrofon des ganzen Macs, z. B. AirPods. Rein, damit die Tests sie
/// prüfen können (main.swift hat Code auf oberster Ebene und gehört nicht ins Testziel).
enum DeviceKey {

    /// Festes Gerät aus den Einstellungen: UID geprüft wie von Gnotchi, Name bereinigt und gekürzt. Leer/ungültig → keines
    /// (die Taste schaltet dann reihum).
    nonisolated static func fixed(_ settings: [String: Any]) -> (uid: String?, name: String?) {
        guard let uid = settings["device"] as? String, DeckWire.isValidDeviceUID(uid) else { return (nil, nil) }
        let name = (settings["deviceName"] as? String)
            .map { String(LiveText.sanitize($0).prefix(60)) }
            .flatMap { $0.isEmpty ? nil : $0 }
        return (uid, name)
    }

    /// Bild und Titel. Mit festem Gerät leuchtet die Taste nur, wenn es das eingestellte ist, und sagt „nicht da“, wenn es fehlt
    /// (AirPods im Etui). Ohne festes Gerät zeigt sie das eingestellte.
    nonisolated static func look(_ s: DeckWire.Status?, input: Bool, fixed: String?, fixedName: String?,
                                 connected: Bool) -> (image: String, title: String) {
        let on = input ? "key-sysin" : "key-sysout"
        let off = on + "-off"
        guard connected else { return (off, "Gnotchi aus") }
        guard let s, !s.outputs.isEmpty else { return (off, fixedName ?? "…") }
        guard let fixed else { return (on, s.outputs.first { $0.uid == s.output }?.name ?? "?") }
        let name = s.outputs.first { $0.uid == fixed }?.name ?? fixedName ?? "Gerät"
        if s.output == fixed { return (on, name) }
        return s.outputs.contains { $0.uid == fixed } ? (off, name) : (off, "\(name)\nnicht da")
    }
}
