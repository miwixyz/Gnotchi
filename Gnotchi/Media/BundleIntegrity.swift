import Foundation
import Security

/// G2: /usr/bin/perl prüft keine Signatur. Bevor Gnotchi den Adapter startet, muss das
/// eigene Bundle unverändert sein – Ressourcen (Perl-Skript) und eingebetteter Code
/// (Framework, Test-Programm) sind von der Signatur versiegelt.
///
/// Gültigkeit allein genügt nicht: wer das Skript ändern darf, versiegelt das Bundle per
/// `codesign -fs -` neu. Deshalb zusätzlich die Identität festnageln (Team-Zertifikat).
enum BundleIntegrity {
    /// Gnotchi selbst, signiert von Michaels Team (Apple Development oder Developer ID – beide tragen OU = Team).
    static let appRequirement =
        #"anchor apple generic and identifier "dev.mwlr.gnotchi" and certificate leaf[subject.OU] = "LTKJ6Z2VYB""#

    /// Liefert den OSStatus der Prüfung, damit der Aufrufer die Ursache protokollieren kann
    /// (-67050 Anforderung nicht erfüllt: falsches Team, ad hoc, Dev-Build ohne Team;
    /// -67056/-67062 unsigniert bzw. ohne Siegel; -67054/-67021 verändert).
    /// `requirement == nil` prüft nur die Unversehrtheit (für Tests).
    static func check(_ bundleURL: URL, requirement: String? = appRequirement) -> OSStatus {
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code)
        guard created == errSecSuccess, let code else { return created == errSecSuccess ? errSecInternalError : created }
        var req: SecRequirement?
        if let requirement {
            let parsed = SecRequirementCreateWithString(requirement as CFString, [], &req)
            guard parsed == errSecSuccess else { return parsed }
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckNestedCode | kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        return SecStaticCodeCheckValidity(code, flags, req)
    }

    static func isIntact(_ bundleURL: URL, requirement: String? = appRequirement) -> Bool {
        check(bundleURL, requirement: requirement) == errSecSuccess
    }
}
