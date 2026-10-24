import CryptoKit
import Foundation
import LocalAuthentication
import os
import Security

/// Schlüssel für den Zwischenablage-Verlauf (0.11.0, docs/SECURE-DESIGN.md G38/G39).
///
/// Beide liegen im **Schutzklassen-Schlüsselbund** in Gnotchis eigener Gruppe – kein anderer Prozess kommt an sie,
/// auch nicht das Mitteilungs-Hilfsprogramm oder der Perl-Adapter. Das verlangt das eingebettete Provisioning-Profil
/// (`scripts/profile.sh`).
/// - `main` verschlüsselt den Verlauf; nur auf diesem Gerät, lesbar nach dem ersten Entsperren.
/// - `vault` verschlüsselt den Tresor; Lesen nur nach Touch ID bzw. Mac-Passwort (`.userPresence`), die Sperre ist
///   damit kryptografisch und nicht nur ein Dialog.
/// Nie protokolliert: Schlüssel, Längen, Inhalte – nur Statuscodes.
enum ClipboardKeys {
    static let service = "dev.mwlr.gnotchi.zwischenablage"
    static let accessGroup = "LTKJ6Z2VYB.dev.mwlr.gnotchi"
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "zwischenablage")

    enum Account: String { case main = "verlauf", vault = "tresor" }

    enum KeyError: Error, Equatable {
        case status(OSStatus)
        case cancelled
        case malformed
    }

    /// Verlauf-Schlüssel holen, beim ersten Mal anlegen.
    static func mainKey() throws -> SymmetricKey {
        try loadOrCreate(.main, context: nil)
    }

    /// Tresor-Schlüssel holen (fragt Touch ID/Passwort, solange `context` nicht schon bestätigt ist).
    /// Blockiert, solange der Dialog offen ist – nie auf dem Hauptthread aufrufen.
    static func vaultKey(context: LAContext) throws -> SymmetricKey {
        dispatchPrecondition(condition: .notOnQueue(.main))
        return try loadOrCreate(.vault, context: context)
    }

    /// „Zwischenablage zurücksetzen“: beide Schlüssel weg → alles Verschlüsselte ist unlesbar, auch in Sicherungen.
    static func deleteAll() throws {
        for account in [Account.main, .vault] {
            let status = SecItemDelete(baseQuery(account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError.status(status) }
        }
    }

    /// Kontext für den Tresor. Ein bestätigter Kontext bleibt gültig, bis er verworfen wird – die 5 Minuten (G39)
    /// misst deshalb `ClipboardLink`. Systemseitige Wiederverwendung AUS: Gemessen 24.10. – mit 300 s fragte ein neuer
    /// Kontext nicht, wenn kurz vorher per Touch ID entsperrt wurde, und der Tresor blieb offen.
    static func makeVaultContext() -> LAContext {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        context.localizedReason = String(localized: "Tresor öffnen")
        return context
    }

    // MARK: - Intern

    private static func baseQuery(_ account: Account) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account.rawValue,
         kSecAttrAccessGroup as String: accessGroup,
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: false]
    }

    private static func loadOrCreate(_ account: Account, context: LAContext?) throws -> SymmetricKey {
        switch read(account, context: context) {
        case .success(let key):
            return key
        case .failure(.status(errSecItemNotFound)):
            try create(account)
            switch read(account, context: context) {
            case .success(let key): return key
            case .failure(let error): throw error
            }
        case .failure(let error):
            throw error
        }
    }

    private static func read(_ account: Account, context: LAContext?) -> Result<SymmetricKey, KeyError> {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if let context { query[kSecUseAuthenticationContext as String] = context }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == 32 else { return .failure(.malformed) }
            return .success(SymmetricKey(data: data))
        case errSecUserCanceled, errSecAuthFailed:
            return .failure(.cancelled)
        default:
            return .failure(.status(status))
        }
    }

    private static func create(_ account: Account) throws {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw KeyError.status(errSecAllocate)
        }
        var query = baseQuery(account)
        query[kSecValueData as String] = Data(bytes)
        switch account {
        case .main:
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .vault:
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &error) else {
                throw KeyError.status(errSecParam)
            }
            query[kSecAttrAccessControl as String] = access
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            log.error("Schlüssel anlegen fehlgeschlagen: \(status, privacy: .public)")
            throw KeyError.status(status)
        }
    }
}

#if DEBUG
/// Messpunkt 24.10. (nur Testfassung, `open Gnotchi.app --args --clipboard-keychain-probe`):
/// Schutzklassen-Schlüsselbund mit Profil, Touch ID, 5-Minuten-Wiederverwendung. Protokolliert nur Codes/Dauer.
enum ClipboardKeysProbe {
    private static let log = ProbeLog()

    /// `log show` ist in der Claude-Shell blind (24.10. gemessen: 0 Zeilen, auch systemweit) → zusätzlich Datei.
    struct ProbeLog {
        let url = URL(fileURLWithPath: "/tmp/gnotchi-keychain-probe.log")
        func notice(_ text: String) {
            Logger(subsystem: "dev.mwlr.gnotchi", category: "zwischenablage-messung").notice("\(text, privacy: .public)")
            let line = "\(Date().formatted(date: .omitted, time: .standard)) \(text)\n"
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    static func runIfRequested() {
        guard CommandLine.arguments.contains("--clipboard-keychain-probe") else { return }
        Thread.detachNewThread {
            func step(_ name: String, _ body: () throws -> SymmetricKey) -> SymmetricKey? {
                let start = Date()
                do {
                    let key = try body()
                    log.notice("MESSUNG \(name): ok \(String(format: "%.2f", Date().timeIntervalSince(start))) s")
                    return key
                } catch {
                    log.notice("MESSUNG \(name): \(String(describing: error)) \(String(format: "%.2f", Date().timeIntervalSince(start))) s")
                    return nil
                }
            }
            log.notice("MESSUNG start")
            let main1 = step("verlauf-1") { try ClipboardKeys.mainKey() }
            let main2 = step("verlauf-2") { try ClipboardKeys.mainKey() }
            log.notice("MESSUNG verlauf gleich: \(main1 != nil && main1 == main2)")
            let context = ClipboardKeys.makeVaultContext()
            let vault1 = step("tresor-1 (Touch ID erwartet)") { try ClipboardKeys.vaultKey(context: context) }
            let vault2 = step("tresor-2 gleicher Kontext (kein Dialog erwartet)") { try ClipboardKeys.vaultKey(context: context) }
            log.notice("MESSUNG tresor gleich: \(vault1 != nil && vault1 == vault2)")
            let fresh = ClipboardKeys.makeVaultContext()
            _ = step("tresor-3 neuer Kontext (Touch ID erwartet)") { try ClipboardKeys.vaultKey(context: fresh) }
            log.notice("MESSUNG ende")
        }
    }
}
#endif
