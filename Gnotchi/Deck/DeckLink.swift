import AppKit
import OSLog
import Security

/// Stream Deck (0.35.0, SECURE-DESIGN G59): Socket `deck.sock` für das eigene Plugin „GnotchiDeck“, solange „Stream Deck“ an ist.
///
/// - Vor dem ersten Byte geprüft: Peer = Developer ID + `dev.mwlr.gnotchi.deck`, **und** sein Elternprozess = Elgatos Stream Deck.
/// - Befehle nur aus der festen Liste (DeckWire.parse), höchstens 50/s, eine Verbindung.
/// - Solange das Plugin verbunden ist, zählt es als Betrachter des Mixers (Abfrage läuft), und Gnotchi meldet den Stand der
///   beobachteten Apps zurück – nur bei Änderung. Nie Inhalte ins Protokoll (G8).
@MainActor
final class DeckLink: NotchPart {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "streamdeck")
    nonisolated static let requirement = LiveText.peerRequirement(identifier: DeckWire.pluginID)
    nonisolated static let viewer = "streamdeck"

    private let mixer: MixerModel
    private let controller: DeckController
    private var server: PeerSocketServer<DeckWire.Command>?
    private var connected = false
    private var timer: Timer?
    /// Zuletzt gemeldeter Stand je beobachteter App: nur Änderungen gehen raus.
    private var lastSent: [String: DeckWire.Status] = [:]

    init(activity: ActivityModel) {
        mixer = activity.mixer
        controller = DeckController(mixer: activity.mixer, media: activity.media)
    }

    func start() {
        guard server == nil, let dir = LiveTextLink.directory else { return }
        var req: SecRequirement?
        var parent: SecRequirement?
        guard SecRequirementCreateWithString(Self.requirement as CFString, [], &req) == errSecSuccess, let req,
              SecRequirementCreateWithString(DeckWire.streamDeckRequirement as CFString, [], &parent) == errSecSuccess, let parent else {
            return Self.log.error("Stream Deck: Anforderung ungültig")
        }
        let s = PeerSocketServer<DeckWire.Command>(
            directory: dir, fileName: DeckWire.socketName, label: "Stream Deck", peer: "Plugin",
            requirement: req, maxFrame: DeckWire.maxFrame, coalesce: false, perSecond: DeckWire.maxPerSecond,
            parentRequirement: parent,
            parse: { DeckWire.parse($0) },
            onValue: { [weak self] c in Task { @MainActor in self?.receive(c) } })
        do {
            try s.start()
        } catch {
            return Self.log.error("Stream Deck aus: \(String(describing: error), privacy: .public)")
        }
        server = s
    }

    func stop() {
        server?.stop()
        server = nil
        disconnected()
    }

    private func receive(_ c: DeckWire.Command?) {
        guard let c else { return disconnected() }
        if !connected {
            connected = true
            mixer.setVisible(Self.viewer, true, slow: true)
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                MainActor.assumeIsolated { [weak self] in self?.push(all: false) }
            }
            timer?.tolerance = 0.1
            Self.log.notice("Stream Deck: Plugin verbunden")
        }
        controller.handle(c)
        switch c {
        case .watch: push(all: true)
        case .gain, .mute, .play: push(all: false)
        case .hello: break
        }
    }

    private func disconnected() {
        guard connected else { return }
        connected = false
        timer?.invalidate()
        timer = nil
        lastSent = [:]
        controller.reset()
        mixer.setVisible(Self.viewer, false)
        Self.log.notice("Stream Deck: Plugin getrennt")
    }

    /// Stand der beobachteten Apps senden; ohne `all` nur, was sich geändert hat.
    private func push(all: Bool) {
        guard connected, let server else { return }
        let current = controller.statuses()
        let keep = Set(current.map(\.app))
        lastSent = lastSent.filter { keep.contains($0.key) }
        for s in current where all || lastSent[s.app] != s {
            lastSent[s.app] = s
            server.send(DeckWire.encode(s))
        }
    }

    // MARK: Plugin installieren

    nonisolated static var pluginSource: URL? {
        Bundle.main.resourceURL?.appendingPathComponent(DeckWire.pluginFolder, isDirectory: true)
    }

    enum InstallError: Error, Equatable { case missing, unsigned, pack }

    /// Paket für Stream Deck im Prozess packen (libarchive, G32) und an Stream Deck übergeben. Stream Deck fragt selbst nach;
    /// Gnotchi schreibt nie in Elgatos Ordner. Nur ein Plugin mit gültiger eigener Signatur wird übergeben.
    static func installPlugin() -> Result<Void, InstallError> {
        guard let src = pluginSource, FileManager.default.fileExists(atPath: src.path) else { return .failure(.missing) }
        guard isGenuinePlugin(src.appendingPathComponent(DeckWire.executable)) else { return .failure(.unsigned) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("GnotchiDeck-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            let r = try ShelfZip.create([src], password: nil, directory: dir, base: "Gnotchi",
                                        ext: "streamDeckPlugin", keepExecutable: true)
            NSWorkspace.shared.open(r.url)
            log.notice("Stream Deck: Plugin-Paket übergeben")
            return .success(())
        } catch {
            log.error("Stream Deck: Paket nicht gepackt")
            return .failure(.pack)
        }
    }

    nonisolated static func isGenuinePlugin(_ url: URL) -> Bool {
        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess
    }
}
