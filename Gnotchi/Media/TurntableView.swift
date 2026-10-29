import AppKit
import CoreImage
import SwiftUI

/// Plattenspieler als Live-Hintergrund (0.17.0, specs/2026-10-27-gnotchi-0.17.0-plattenspieler.md).
/// Grundlage sind drei KI-Fotos (Michael 27.10.: Bild-KI, ausnahmsweise ohne Kennzeichnung), zerlegt in Ebenen
/// (tools/turntable-ebenen.py): Gerät ohne Arm, Platte kreisrund entzerrt (dreht sich, Michael: „Wie eine Platte eben“),
/// stehender Glanz, Tonarm (Lager fest, Rohr dreht ums Lager und wandert mit dem Titel nach innen), Arm in der Ablage.
/// Perspektive: TurntableGeometry. Titel/Interpret/Cover sind Fremddaten → nur `Text(verbatim:)` (G5/G6).
enum TurntableArt {
    /// Bildgröße des Geräts (Gerätebild-Pixel); alle Ebenen außer Platte/Glanz haben diese Größe.
    static let size = CGSize(width: 1991, height: 1080)
    /// Achse: Kopf aus dem Foto, über dem Etikett.
    static let spindleOrigin = CGPoint(x: 824, y: 314)
    static let spindleSize = CGSize(width: 36, height: 40)
    /// Start/Stopp-Knopf im Sockelbild (Pixel, gemessen 27.10.): schräges Viereck wegen der Perspektive,
    /// oben links, oben rechts, unten rechts, unten links.
    static let startStop = [CGPoint(x: 100, y: 675), CGPoint(x: 275, y: 675), CGPoint(x: 254, y: 774), CGPoint(x: 70, y: 774)]
    /// 33⅓ U/min in Grad pro Sekunde.
    static let degreesPerSecond = 33.333 / 60 * 360

    @MainActor static let base = load("tt-basis", "webp")
    @MainActor static let plate = load("tt-platte", "webp")
    @MainActor static let sheen = load("tt-glanz", "webp")
    @MainActor static let armTube = load("tt-arm-rohr", "webp")
    @MainActor static let armBearing = load("tt-arm-lager", "webp")
    @MainActor static let armRest = load("tt-arm-ablage", "webp")
    /// Eigene weiche Schatten der Armteile (aus der Armform erzeugt, nicht fotografiert) – bewegen sich mit.
    @MainActor static let armTubeShadow = load("tt-arm-rohr-schatten", "webp")
    @MainActor static let armBearingShadow = load("tt-arm-lager-schatten", "webp")
    @MainActor static let armRestShadow = load("tt-arm-ablage-schatten", "webp")
    @MainActor static let spindle = load("spindel", "png")

    @MainActor private static func load(_ name: String, _ ext: String) -> NSImage? {
        AppResources.bundle.url(forResource: name, withExtension: ext).flatMap(NSImage.init(contentsOf:))
    }
}

/// Drehwinkel über die Zeit: gleichmäßig beim Spielen, bei Pause weich auslaufend (Zeitkonstante `tau`).
struct TurntableSpin: Equatable {
    var anchorAngle: Double = 0
    var anchorDate = Date.distantPast
    var playing = false
    /// Nach einer Pause: läuft aus. Ein Plattenspieler, der nie gespielt hat, steht still (Test 27.10.: sonst +90°).
    var coasting = false
    static let tau = 0.45

    func angle(at t: Date) -> Double {
        let dt = max(0, t.timeIntervalSince(anchorDate))
        let w = TurntableArt.degreesPerSecond
        if playing { return anchorAngle + w * dt }
        return coasting ? anchorAngle + w * Self.tau * (1 - exp(-dt / Self.tau)) : anchorAngle
    }

    /// Läuft die Animation noch (Spielen oder Auslaufen)?
    func moving(at t: Date) -> Bool { playing || (coasting && t.timeIntervalSince(anchorDate) < Self.tau * 6) }

    /// Zustandswechsel ohne Sprung: der neue Abschnitt beginnt beim aktuellen Winkel.
    func switched(to playing: Bool, at t: Date) -> TurntableSpin {
        guard playing != self.playing else { return self }
        return TurntableSpin(anchorAngle: angle(at: t).truncatingRemainder(dividingBy: 360), anchorDate: t, playing: playing,
                             coasting: !playing)
    }
}

/// Zwei Farben für den Hintergrund aus dem Cover (Durchschnitt obere linke bzw. untere rechte Hälfte), abgedunkelt,
/// damit weiße Schrift lesbar bleibt. Ohne Cover ein ruhiges Dunkelgrau.
enum TurntableColors {
    struct RGB: Equatable { var r, g, b: Double }
    /// 3 × 3 Farbinseln für den Verlauf (Zeile für Zeile von oben), Lichtschein hinter dem Gerät.
    struct Palette: Equatable {
        var mesh: [Color]
        var glow: Color
        /// Farbe der Neonschrift: kräftigste Coverfarbe in voller Helligkeit.
        var neon: Color
    }
    static let fallback = Palette(mesh: [0.24, 0.22, 0.2, 0.17, 0.15, 0.13, 0.08, 0.07, 0.06].map { Color(white: $0) },
                                  glow: Color(white: 0.4),
                                  neon: Color(red: 1, green: 0.25, blue: 0.6))
    /// Helligkeit je Zeile: oben Raum, unten „Boden“ – Michael 27.10.: „interessanterer Verlauf“.
    static let rowLevels = [0.55, 0.4, 0.17]
    @MainActor private static var cache: (ObjectIdentifier, Palette)?

    @MainActor static func palette(for image: NSImage?) -> Palette {
        guard let image else { return fallback }
        if let cache, cache.0 == ObjectIdentifier(image) { return cache.1 }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return fallback }
        let ci = CIImage(cgImage: cg)
        let e = ci.extent
        var samples: [RGB] = []
        for row in 0..<3 {
            for col in 0..<3 {
                // CoreImage zählt von unten: Zeile 0 (oben) ist das oberste Drittel.
                let rect = CGRect(x: e.minX + CGFloat(col) * e.width / 3, y: e.maxY - CGFloat(row + 1) * e.height / 3,
                                  width: e.width / 3, height: e.height / 3)
                guard let c = average(ci, rect) else { return fallback }
                samples.append(c)
            }
        }
        let result = palette(from: samples)
        cache = (ObjectIdentifier(image), result)
        return result
    }

    /// Reine Rechnung (getestet): neun Proben → Farbinseln je Zeile abgedunkelt, Lichtschein aus der kräftigsten Probe.
    nonisolated static func palette(from samples: [RGB]) -> Palette {
        guard samples.count == 9 else { return fallback }
        let mesh = samples.enumerated().map { shade($0.element, rowLevels[$0.offset / 3]) }
        let vivid = samples.max { saturation($0) < saturation($1) } ?? samples[4]
        // Graue Cover: klassisches Neon-Pink statt fahlem Grau.
        let neon = saturation(vivid) < 0.25 ? fallback.neon : brightest(vivid)
        return Palette(mesh: mesh, glow: shade(vivid, 0.85), neon: neon)
    }

    nonisolated static func saturation(_ c: RGB) -> Double {
        let hi = max(c.r, c.g, c.b), lo = min(c.r, c.g, c.b)
        return hi < 0.001 ? 0 : (hi - lo) / hi
    }

    /// Einmal anlegen, nicht je Aufruf: 9 neue Kontexte je Cover kosteten ~75 ms auf dem Hauptthread,
    /// ein gemeinsamer ~6 ms bei identischem Ergebnis (gemessen 28.10., BAMA-Check).
    @MainActor private static let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    @MainActor private static func average(_ img: CIImage, _ rect: CGRect) -> RGB? {
        guard let f = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: img, kCIInputExtentKey: CIVector(cgRect: rect)]),
              let out = f.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        ciContext.render(out, toBitmap: &px, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: nil)
        return RGB(r: Double(px[0]) / 255, g: Double(px[1]) / 255, b: Double(px[2]) / 255)
    }

    /// Volle Helligkeit bei gleichem Farbton (Neon) – anders als `shade`, das nie aufhellt.
    nonisolated static func brightest(_ c: RGB) -> Color {
        let m = max(c.r, c.g, c.b, 0.001)
        return Color(red: c.r / m, green: c.g / m, blue: c.b / m)
    }

    /// Helligkeit auf `level` begrenzen, Farbton behalten; dunkle Farben werden nicht aufgehellt.
    nonisolated static func shade(_ c: RGB, _ level: Double) -> Color {
        let m = max(c.r, c.g, c.b, 0.001)
        let k = min(1, level / m)
        return Color(red: c.r * k, green: c.g * k, blue: c.b * k)
    }
}

/// Der ganze Plattenspieler: Hülle links, Gerät (Ebenen), darunter Titel und Knopfleiste.
struct TurntableView: View {
    let media: NowPlayingModel
    /// Breite des Geräts in Punkten; Hülle und Text richten sich danach.
    let deckWidth: CGFloat
    /// Neonschrift „Now Playing“ darüber (Einstellung).
    var neon = false
    /// Start/Stopp-Knopf am Sockel klickbar (Einstellung `desktopMusicTonearm`, ab Werk aus).
    var tonearm = false
    @State private var spin = TurntableSpin()
    @State private var arm = TurntableArmMotion()
    @State private var hovering = false

    private var scale: CGFloat { deckWidth / TurntableArt.size.width }

    /// Hülle in Gerätebreiten (Michael 27.10.: „Maßstab passt gar nicht“). Platte im Bild 0,565 Gerätebreiten (aus
    /// `TurntableGeometry.plane`). Vorher 0,42 (74 % der Platte); echter LP-Maßstab wäre 0,59 (31,4 : 30 cm) – wirkte
    /// aufrecht neben der schräg gesehenen Platte zu groß. Michael wählte den Mittelweg: 92 % der Platte.
    static let sleeveRatio: CGFloat = 0.52
    static let sleeveOverlap: CGFloat = 0.06
    static let sleeveLift: CGFloat = 0.015
    /// Reihe Hülle + Gerät in Gerätebreiten (für das Fenster).
    static let rowWidthRatio = 1 + sleeveRatio - sleeveOverlap
    static let rowHeightRatio = max(TurntableArt.size.height / TurntableArt.size.width, sleeveRatio + sleeveLift)

    var body: some View {
        let info = media.info
        let playing = info?.isPlaying ?? false
        VStack(spacing: deckWidth * 0.03) {
            if neon {
                TurntableNeon(color: TurntableColors.palette(for: media.artwork).neon, lit: playing, deckWidth: deckWidth)
            }
            HStack(alignment: .bottom, spacing: -deckWidth * Self.sleeveOverlap) {
                sleeve.zIndex(0)
                deck(playing: playing).zIndex(1)
            }
            VStack(spacing: 4) {
                Text(verbatim: info?.title ?? "").font(.system(size: max(15, deckWidth * 0.026), weight: .semibold))
                Text(verbatim: [info?.artist, info?.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: max(12, deckWidth * 0.016))).opacity(0.8)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
            .lineLimit(1)
            .frame(maxWidth: deckWidth * 1.2)
            PlayerButtons(model: media, isPlaying: playing, iconSize: 16, spacing: 18)
                .padding(.horizontal, 16).padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.5)))
                .frame(height: DesktopMusicLink.controlsHeight)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
        }
        .onHover { hovering = $0 }
        .onAppear {
            spin = spin.switched(to: playing, at: Date())
            arm = arm.switched(toPlaying: playing, at: .distantPast)   // beim Öffnen ohne Schwenk
        }
        .onChange(of: playing) { _, now in
            let t = Date()
            spin = spin.switched(to: now, at: t)
            arm = arm.switched(toPlaying: now, at: t)
        }
        // Titelwechsel: Arm fährt vom alten Winkel zurück zur Einlaufrille (wie beim Auflegen des nächsten Stücks).
        .onChange(of: info) { old, new in
            guard let old, let new, old.title != new.title else { return }
            let t = Date()
            arm = arm.retracked(from: arm.needleAngle(progress: Self.progress(old, at: t), at: t), at: t)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: info?.title ?? ""))
    }

    static func progress(_ info: NowPlayingInfo?, at t: Date) -> Double {
        guard let info, let d = info.duration, d > 0 else { return 0 }
        return info.elapsed(at: t) / d
    }

    private var sleeve: some View {
        let side = deckWidth * Self.sleeveRatio
        return cover
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(LinearGradient(colors: [.white.opacity(0.14), .clear, .black.opacity(0.2)], startPoint: .topLeading,
                                    endPoint: .bottomTrailing))
            .rotation3DEffect(.degrees(22), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .shadow(color: .black.opacity(0.5), radius: 18, x: 8, y: 14)
            .padding(.bottom, deckWidth * Self.sleeveLift)   // steht auf Höhe der Füße
            .onTapGesture { DesktopMusicView.bringToFront(media.info?.appBundleID) }
    }

    private func deck(playing: Bool) -> some View {
        let now = Date()
        let moving = spin.moving(at: now) || arm.moving(at: now) || playing
        return ZStack(alignment: .topLeading) {
            contactShadow
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { ctx in
                layers(at: ctx.date)
                // Keine Tönung mehr (0.17.5): `softLight` wirkte im echten Fenster nie als Licht, sondern lag als deckender
                // Schleier in der Coverfarbe auf dem Gerät – seit 0.17.0, ImageRenderer-Testbilder zeigten es nicht.
                // Messpunkt 27.10. am Schreibtisch: ohne Tönung klar (Michael: „jetzt passt es“).
            }
        }
        .frame(width: deckWidth, height: TurntableArt.size.height * scale, alignment: .topLeading)
        .shadow(color: .black.opacity(0.28), radius: 6, y: 4)
        // Start/Stopp-Knopf des Fotos (Michael 27.10.: „Wie wäre es mit dem Start/Stopp Knopf als realistischen“).
        // Ersetzt den Tonarm-Griff: Der wanderte beim Spielen mit, Klicks kamen dort nie an (Messpunkt 27.10.:
        // fünfmal „berührt“, kein Klick). Der Knopf steht fest, oberste Schicht über dem Arm.
        .overlay(alignment: .topLeading) {
            if tonearm { startStopButton }
        }
    }

    private var startStopButton: some View {
        let shape = TurntableStartStopShape(corners: TurntableArt.startStop.map { CGPoint(x: $0.x * scale, y: $0.y * scale) })
        return Button { media.playPause() } label: {
            Color.clear.contentShape(shape)
        }
        .buttonStyle(TurntablePressStyle(shape: shape))
        .frame(width: deckWidth, height: TurntableArt.size.height * scale)
        .help("Start/Stopp")
        .accessibilityLabel(Text(verbatim: media.info?.isPlaying == true ? "Stopp" : "Start"))
    }

    /// Armwinkel jetzt: Ablage → Platte nach Schwenk-Phase, auf der Platte nach Titelfortschritt plus Mitlauf.
    private func tubeAngle(at t: Date) -> Double {
        let f = arm.phase(at: t)
        let target = arm.needleAngle(progress: Self.progress(media.info, at: t), at: t)
        let rest = TurntableGeometry.restAngle
        let wob = TurntableGeometry.wobble(plateAngle: spin.angle(at: t))
        return rest + f * (target + wob.lateral - rest)
    }

    /// Alle beweglichen Ebenen für einen Zeitpunkt: Platte dreht, Arm schwenkt bzw. wandert mit dem Titel.
    func layers(at t: Date) -> some View {   // intern: Testbild (TurntableTests)
        let s = Double(scale)
        let toDeck = Homography.scale(s) * TurntableGeometry.circle
        let n = TurntableGeometry.circleSize
        let f = arm.phase(at: t)
        let target = arm.needleAngle(progress: Self.progress(media.info, at: t), at: t)
        let rest = TurntableGeometry.restAngle
        // Auf der Platte folgt der Arm ihrem Lauf (nur so weit er aufliegt: mal f).
        let plateAngle = spin.angle(at: t)
        let wob = TurntableGeometry.wobble(plateAngle: plateAngle)
        let tubeAngle = tubeAngle(at: t)
        let tube = Homography.scale(s) * TurntableGeometry.arm(tubeAngle) * Homography.scale(1 / s)
        // Welligkeit: nur der Schatten rückt näher/weiter, der Arm bleibt starr.
        let tubeShadow = Homography.scale(s) * TurntableGeometry.shadowOffset(wob.shadowShift * f)
            * TurntableGeometry.arm(tubeAngle) * Homography.scale(1 / s)
        let restSwing = Homography.scale(s) * TurntableGeometry.arm(f * (target - rest)) * Homography.scale(1 / s)
        return ZStack(alignment: .topLeading) {
            // Feste Gerätegröße: Die Plattenebene ist 1120 pt groß und würde das Bild sonst mitstrecken (Testbild 27.10.).
            deckArt(TurntableArt.base)
            ZStack {
                art(TurntableArt.plate)
                cover.frame(width: n * TurntableGeometry.labelRadius, height: n * TurntableGeometry.labelRadius)
                    .clipShape(Circle())
            }
            .frame(width: n, height: n)
            .rotationEffect(.degrees(plateAngle))
            .projectionEffect(toDeck.projection)
            art(TurntableArt.sheen).frame(width: n, height: n).projectionEffect(toDeck.projection).opacity(0.9)
            if let spindle = TurntableArt.spindle {
                Image(nsImage: spindle).resizable()
                    .frame(width: TurntableArt.spindleSize.width * scale, height: TurntableArt.spindleSize.height * scale)
                    .offset(x: TurntableArt.spindleOrigin.x * scale, y: TurntableArt.spindleOrigin.y * scale)
            }
            // Ablage-Arm (Pausenfoto) dreht beim Schwenk mit und blendet aus; Spiel-Arm (Lager + Rohr) blendet ein.
            if f < 1 {
                deckArt(TurntableArt.armRestShadow).projectionEffect(restSwing.projection).opacity(1 - f)
                deckArt(TurntableArt.armRest).projectionEffect(restSwing.projection).opacity(1 - f)
            }
            if f > 0 {
                deckArt(TurntableArt.armBearingShadow).opacity(f)
                deckArt(TurntableArt.armTubeShadow).projectionEffect(tubeShadow.projection).opacity(f)
                deckArt(TurntableArt.armBearing).opacity(f)
                deckArt(TurntableArt.armTube).projectionEffect(tube.projection).opacity(f)
            }
        }
        .frame(width: deckWidth, height: TurntableArt.size.height * scale, alignment: .topLeading)
    }

    /// Steht auf dem Boden: weicher Schatten unter dem Sockel, dunkler direkt unter den Füßen.
    private var contactShadow: some View {
        let h = TurntableArt.size.height * scale
        return ZStack {
            Ellipse().fill(.black.opacity(0.55))
                .frame(width: deckWidth * 0.95, height: h * 0.16)
                .blur(radius: deckWidth * 0.03)
                .position(x: deckWidth / 2, y: h * 0.93)
            ForEach([0.12, 0.88], id: \.self) { x in
                Ellipse().fill(.black.opacity(0.6))
                    .frame(width: deckWidth * 0.12, height: h * 0.05)
                    .blur(radius: deckWidth * 0.01)
                    .position(x: deckWidth * x, y: h * 0.985)
            }
        }
        .frame(width: deckWidth, height: h)
    }

    @ViewBuilder private func art(_ image: NSImage?) -> some View {
        if let image { Image(nsImage: image).resizable().interpolation(.high) }
    }

    /// Ebene in Gerätegröße (Punkte), oben links bündig – Grundlage für die Projektion.
    private func deckArt(_ image: NSImage?) -> some View {
        art(image).frame(width: deckWidth, height: TurntableArt.size.height * scale)
    }

    @ViewBuilder private var cover: some View {
        if let image = media.artwork {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
        } else {
            ZStack {
                Color(white: 0.18)
                Image(systemName: "music.note").resizable().scaledToFit().padding(deckWidth * 0.05)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}

/// Neonschrift „Now Playing“ (Michael 27.10.): heller Röhrenkern, Leuchten in der Coverfarbe. Beim Start flackert
/// sie an, bei Pause glimmt sie nur (Röhre aus, Farbe noch zu ahnen).
struct TurntableNeon: View {
    let color: Color
    let lit: Bool
    let deckWidth: CGFloat
    @State private var flicker = 1.0

    static func height(deckWidth: CGFloat) -> CGFloat { deckWidth * 0.11 }

    /// (Helligkeit, Dauer in ms): Zünden einer Röhre bzw. kurzes Zucken.
    static let ignition: [(Double, Int)] = [(0.1, 90), (0.85, 60), (0.05, 160), (1, 50), (0.2, 110), (0.75, 140),
                                            (0.3, 70), (1, 90), (0.6, 60), (1, 0)]
    static let buzz: [(Double, Int)] = [(0.45, 60), (1, 80), (0.65, 50), (1, 0)]

    @MainActor static func play(_ steps: [(Double, Int)], set: (Double) -> Void) async {
        for (v, ms) in steps {
            guard !Task.isCancelled else { return }
            set(v)
            if ms > 0 { try? await Task.sleep(for: .milliseconds(ms)) }
        }
    }

    var body: some View {
        let size = deckWidth * 0.075
        // Neonderthaw (OFL, mitgeliefert): eigens für Neon, doppelte Linie wie eine Röhre. Michael 27.10.: Druckschrift
        // „zu technisch“, dann aus sechs Proben gewählt. Fehlt sie (Registrierung gescheitert), Snell Roundhand.
        Text(verbatim: "Now Playing")
            .font(NSFont(name: "Neonderthaw-Regular", size: size) != nil
                  ? .custom("Neonderthaw-Regular", size: size * 1.25) : .custom("SnellRoundhand-Black", size: size))
            .foregroundStyle(lit ? Color.white.opacity(0.95) : color.opacity(0.35))
            .shadow(color: lit ? color : .clear, radius: size * 0.06)
            .shadow(color: lit ? color : .clear, radius: size * 0.22)
            .shadow(color: lit ? color.opacity(0.85) : .clear, radius: size * 0.55)
            .opacity(lit ? flicker : 1)
            .frame(height: Self.height(deckWidth: deckWidth))
            .animation(.easeOut(duration: 0.25), value: lit)
            .task(id: lit) {
                guard lit else { return }
                // Erst nach dem Einblenden der Anzeige (0,8 s) – vorher lief das Flackern unsichtbar ab (Michael 27.10.:
                // „flackert nicht“). Dann wie eine anspringende Röhre, unregelmäßig, gut 1 s.
                try? await Task.sleep(for: .milliseconds(900))
                await Self.play(Self.ignition) { flicker = $0 }
                // Beim Spielen zuckt die Röhre ab und zu kurz (alle 18–40 s).
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Double.random(in: 18...40)))
                    guard !Task.isCancelled else { return }
                    await Self.play(Self.buzz) { flicker = $0 }
                }
            }
            .accessibilityHidden(true)
    }
}

/// Hintergrund über den ganzen Bildschirm (unter den Schreibtisch-Symbolen): Farbinseln aus dem Cover, Lichtschein
/// hinter dem Plattenspieler, dunklerer Boden; weicher Wechsel beim Titelwechsel.
struct TurntableBackdrop: View {
    let media: NowPlayingModel
    @State private var palette = TurntableColors.fallback

    var body: some View {
        GeometryReader { geo in
            ZStack {
                MeshGradient(width: 3, height: 3,
                             points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.55, 0.42], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                             colors: palette.mesh)
                RadialGradient(colors: [palette.glow.opacity(0.55), palette.glow.opacity(0.14), .clear],
                               center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: geo.size.width * 0.3)
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: UnitPoint(x: 0.5, y: 0.62), endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .onAppear { palette = TurntableColors.palette(for: media.artwork) }
        .onChange(of: media.artwork) { _, img in
            withAnimation(.easeInOut(duration: 1.5)) { palette = TurntableColors.palette(for: img) }
        }
    }
}

/// Viereck aus vier Ecken (Start/Stopp-Knopf in Perspektive).
struct TurntableStartStopShape: Shape {
    let corners: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addLines(corners)
        p.closeSubpath()
        return p
    }
}

/// Gedrückt: Knopf kurz dunkler, wie eingedrückt.
struct TurntablePressStyle: ButtonStyle {
    let shape: TurntableStartStopShape
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(shape.fill(Color.black.opacity(configuration.isPressed ? 0.22 : 0)).allowsHitTesting(false))
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
