import AppKit
import Carbon.HIToolbox

/// Globale Tastenkürzel über Carbon `RegisterEventHotKey` – braucht **keine** Freigabe, kein Event-Tap (G1).
/// Gemessen 24.10.: Ctrl+< kommt so an (Tastencode 50 auf deutscher ISO-Tastatur). Grenze: Fängt eine andere App
/// dieselbe Kombination per Event-Tap ab (PastePal), meldet die Registrierung trotzdem Erfolg – nicht erkennbar.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false
    private var nextID: UInt32 = 1

    /// Registriert ein Kürzel; Rückgabe = Kennung zum Abmelden (nil bei Fehler).
    func register(_ hotKey: Preferences.HotKey, action: @escaping () -> Void) -> UInt32? {
        installHandler()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, EventHotKeyID(signature: 0x474E4F54, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        refs[id] = ref
        handlers[id] = action
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }

    fileprivate func fire(_ id: UInt32) { handlers[id]?() }

    private func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            MainActor.assumeIsolated { HotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Vorschlag „Ctrl+<“: welcher Tastencode ergibt im aktiven Layout „<“? (24.10.: nicht fest 10, sondern 50.)
    static func defaultPanelHotKey() -> Preferences.HotKey? {
        keyCode(producing: "<").map { Preferences.HotKey(keyCode: $0, modifiers: UInt32(controlKey)) }
    }

    static func keyCode(producing character: String) -> UInt32? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        for code in UInt16(0)..<128 {
            var dead: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
            if status == noErr, String(utf16CodeUnits: chars, count: length) == character { return UInt32(code) }
        }
        return nil
    }

    /// Lesbare Form für die Einstellungen, z. B. „⌃<“.
    static func display(_ hotKey: Preferences.HotKey) -> String {
        var out = ""
        if hotKey.modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if hotKey.modifiers & UInt32(optionKey) != 0 { out += "⌥" }
        if hotKey.modifiers & UInt32(shiftKey) != 0 { out += "⇧" }
        if hotKey.modifiers & UInt32(cmdKey) != 0 { out += "⌘" }
        return out + (character(for: UInt16(hotKey.keyCode)) ?? "#\(hotKey.keyCode)")
    }

    private static func character(for code: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var dead: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        guard UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                             OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars) == noErr,
              length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    /// Carbon-Modifikatoren aus einem NSEvent (für die Aufnahme in den Einstellungen).
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var out: UInt32 = 0
        if flags.contains(.control) { out |= UInt32(controlKey) }
        if flags.contains(.option) { out |= UInt32(optionKey) }
        if flags.contains(.shift) { out |= UInt32(shiftKey) }
        if flags.contains(.command) { out |= UInt32(cmdKey) }
        return out
    }
}
