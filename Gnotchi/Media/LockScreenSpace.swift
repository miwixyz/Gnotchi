import AppKit
import os

/// Eigener Fenster-Bereich über dem Sperrbildschirm (0.20.0, specs/2026-11-06-gnotchi-0.20.0-sperrbildschirm.md, G46).
///
/// Öffentliche Fensterebenen (auch `CGShieldingWindowLevel()+1`) verschwinden beim Sperren – gemessen 06.11. unter
/// macOS 27.2. Sichtbar bleibt nur ein Fenster in einem eigenen SkyLight-Space mit absoluter Ebene 400. Das ist eine
/// **private** Schnittstelle: alle Funktionen werden zur Laufzeit gesucht; fehlt eine, ist die Funktion aus
/// (`isAvailable == false`), nie ein Absturz.
///
/// In den Space kommt immer nur **ein** Fenster – das der Sperrkarte (G46). `windows` zählt mit, der Test prüft es.
@MainActor
final class LockScreenSpace {
    nonisolated private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "lockscreen")
    /// Ebene des Space (gemessen 06.11.: 400 liegt über dem Sperrbildschirm).
    nonisolated static let level: Int32 = 400

    private typealias MainConn = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceDestroy = @convention(c) (Int32, UInt64) -> Void
    private typealias SetLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias SpaceList = @convention(c) (Int32, CFArray) -> Void
    private typealias AddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Void
    private typealias RemoveWindows = @convention(c) (Int32, CFArray, CFArray) -> Void

    private struct API {
        let main: MainConn
        let create: SpaceCreate
        let destroy: SpaceDestroy
        let setLevel: SetLevel
        let show: SpaceList
        let hide: SpaceList
        let add: AddWindows
        let remove: RemoveWindows
    }

    /// Einmal pro Programmlauf gesucht. `nil` = mindestens eine Funktion fehlt.
    nonisolated(unsafe) private static let api: API? = {
        guard let lib = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else {
            log.error("SkyLight nicht ladbar")
            return nil
        }
        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let p = dlsym(lib, name) else {
                log.error("SkyLight-Funktion fehlt: \(name, privacy: .public)")
                return nil
            }
            return unsafeBitCast(p, to: T.self)
        }
        guard let main = sym("SLSMainConnectionID", MainConn.self),
              let create = sym("SLSSpaceCreate", SpaceCreate.self),
              let destroy = sym("SLSSpaceDestroy", SpaceDestroy.self),
              let setLevel = sym("SLSSpaceSetAbsoluteLevel", SetLevel.self),
              let show = sym("SLSShowSpaces", SpaceList.self),
              let hide = sym("SLSHideSpaces", SpaceList.self),
              let add = sym("SLSSpaceAddWindowsAndRemoveFromSpaces", AddWindows.self),
              let remove = sym("SLSRemoveWindowsFromSpaces", RemoveWindows.self)
        else { return nil }
        return API(main: main, create: create, destroy: destroy, setLevel: setLevel, show: show, hide: hide,
                   add: add, remove: remove)
    }()

    /// Gibt es unter dieser macOS-Version alles, was gebraucht wird?
    static var isAvailable: Bool { api != nil }

    private let api: API
    private let conn: Int32
    private let space: UInt64
    /// Fensternummern im Space – nie mehr als eins (G46).
    private(set) var windows: [Int] = []

    /// `nil`, wenn eine Funktion fehlt oder der Space nicht entsteht.
    init?() {
        guard let api = Self.api else { return nil }
        let conn = api.main()
        let space = api.create(conn, 1, nil)
        guard conn != 0, space != 0 else {
            Self.log.error("SkyLight-Space nicht angelegt")
            return nil
        }
        let err = api.setLevel(conn, space, Self.level)
        guard err == 0 else {
            Self.log.error("SkyLight-Ebene nicht gesetzt: \(err, privacy: .public)")
            api.destroy(conn, space)
            return nil
        }
        api.show(conn, [NSNumber(value: space)] as CFArray)
        self.api = api
        self.conn = conn
        self.space = space
    }

    /// Das eine Fenster in den Space legen. Ein anderes, schon vorhandenes wird vorher herausgenommen.
    func host(_ window: NSWindow) {
        let number = window.windowNumber
        guard number > 0, windows != [number] else { return }
        release()
        api.add(conn, space, [NSNumber(value: number)] as CFArray, 7)
        windows = [number]
    }

    /// Fenster aus dem Space nehmen (vor dem Schließen).
    func release() {
        guard !windows.isEmpty else { return }
        api.remove(conn, windows.map { NSNumber(value: $0) } as CFArray, [NSNumber(value: space)] as CFArray)
        windows = []
    }

    /// Space abbauen (Funktion aus, App beendet).
    func tearDown() {
        release()
        api.hide(conn, [NSNumber(value: space)] as CFArray)
        api.destroy(conn, space)
    }
}
