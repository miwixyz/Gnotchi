import Foundation

/// Erkennt kopierte Schlüssel und Tokens (0.13.0, docs/SECURE-DESIGN.md G43). Rein, ohne Zustand, getestet.
///
/// - Nur **feste Muster** mit eindeutiger Vorsilbe/Struktur, keine Entropie-Schätzung (Fehlalarm = ein normaler
///   Eintrag würde verdeckt und gelöscht).
/// - Nur wenn die **ganze** Kopie (nach Trimmen von Leerraum) passt. Ein Schlüssel mitten in einem Chat oder einer
///   Codedatei bleibt ein normaler Eintrag (Michael 26.10.).
/// - Nur reiner Text bis 8 KB, Muster verankert und ohne verschachtelte Quantoren (kein ReDoS).
/// - Rückgabe ist die Art zum Anzeigen. Sie geht nie ins Protokoll (verrät den Dienst).
enum SecretDetector {

    static let maxBytes = 8 * 1024

    struct Rule: Sendable {
        let kind: String
        let pattern: String
    }

    // Muster bleiben am Stück – zerteilte Regex sind fehleranfällig.
    // swiftlint:disable line_length
    /// Reihenfolge zählt: spezifische Vorsilben vor allgemeinen (`sk-ant-` vor `sk-`). Quellen je Eintrag in
    /// `specs/2026-10-26-gnotchi-0.13.0-geheimnisse.md`: gitleaks-Standardkonfiguration (MIT, © 2019 Zachary Rice),
    /// Anbieter-Doku, GitHub-Secret-Scanning-Partnerliste. Nur aus trufflehog (AGPL) belegte Formate sind hier aus den
    /// Formatangaben (Vorsilbe, Länge, Zeichensatz) neu geschrieben, nicht übernommen.
    /// Bewusst NICHT erkennbar (kein Präfix → Fehlalarm): Hostinger, Cloudflare alt, Mistral, Twilio, Discord.
    static let rules: [Rule] = [
        // KI-Dienste – spezifische `sk-…` vor allgemeineren.
        Rule(kind: "Anthropic-Schlüssel", pattern: #"^sk-ant-(?:api03|admin01)-[A-Za-z0-9_-]{93}AA$"#),
        Rule(kind: "OpenRouter-Schlüssel", pattern: #"^sk-or-v1-[0-9a-f]{64}$"#),
        Rule(kind: "OpenAI-Schlüssel", pattern: #"^(?:sk-(?:proj|svcacct|admin)-(?:[A-Za-z0-9_-]{74}|[A-Za-z0-9_-]{58})T3BlbkFJ(?:[A-Za-z0-9_-]{74}|[A-Za-z0-9_-]{58})|sk-[A-Za-z0-9]{20}T3BlbkFJ[A-Za-z0-9]{20})$"#),
        Rule(kind: "ElevenLabs-Schlüssel", pattern: #"^sk_[0-9a-f]{48}$"#),
        Rule(kind: "Google-API-Schlüssel", pattern: #"^AIza[0-9A-Za-z_-]{35}$"#),
        Rule(kind: "Gemini-Schlüssel", pattern: #"^AQ\.[A-Za-z0-9_-]{40,80}$"#),
        Rule(kind: "Hugging-Face-Token", pattern: #"^(?:hf_|api_org_)[A-Za-z0-9]{34}$"#),
        Rule(kind: "Replicate-Token", pattern: #"^r8_[A-Za-z0-9_-]{37}$"#),
        Rule(kind: "Groq-Schlüssel", pattern: #"^gsk_[A-Za-z0-9]{52}$"#),
        Rule(kind: "Perplexity-Schlüssel", pattern: #"^pplx-[A-Za-z0-9]{48}$"#),
        Rule(kind: "Firecrawl-Schlüssel", pattern: #"^fc-[A-Za-z0-9]{20,64}$"#),
        Rule(kind: "Apify-Token", pattern: #"^apify_api_[A-Za-z0-9]{36}$"#),
        // Code, Hosting, Infrastruktur
        Rule(kind: "GitHub-Token", pattern: #"^(?:gh[pous]_[A-Za-z0-9]{36}|ghr_[A-Za-z0-9]{36,76}|github_pat_[A-Za-z0-9_]{82})$"#),
        Rule(kind: "GitLab-Token", pattern: #"^glpat-[A-Za-z0-9_.-]{20,300}$"#),
        Rule(kind: "npm-Token", pattern: #"^npm_[A-Za-z0-9]{36}$"#),
        Rule(kind: "AWS-Zugangsschlüssel", pattern: #"^(?:A3T[A-Z0-9]|AKIA|ASIA|ABIA|ACCA)[A-Z2-7]{16}$"#),
        Rule(kind: "Cloudflare-Token", pattern: #"^(?:cfk|cfut|cfat)_[A-Za-z0-9]{40}[0-9a-f]{8}$"#),
        Rule(kind: "Cloudflare-Origin-Schlüssel", pattern: #"^v1\.0-[0-9a-f]{24}-[0-9a-f]{146}$"#),
        Rule(kind: "DigitalOcean-Token", pattern: #"^do[opr]_v1_[0-9a-f]{64}$"#),
        Rule(kind: "Vercel-Token", pattern: #"^vc[pikar]_[A-Za-z0-9]{20,}$"#),
        Rule(kind: "Netlify-Token", pattern: #"^nf[pcoub]_[A-Za-z0-9_]{36}$"#),
        Rule(kind: "Supabase-Schlüssel", pattern: #"^(?:sb_secret_[A-Za-z0-9_-]{20,}|sbp_[a-z0-9]{40})$"#),
        Rule(kind: "Doppler-Token", pattern: #"^dp\.(?:ct|pt|st(?:\.[a-z0-9_-]{2,35})?|sa|scim|audit)\.[A-Za-z0-9]{40,44}$"#),
        Rule(kind: "Rafter-Schlüssel", pattern: #"^RF[A-Za-z0-9]{3}-[0-9a-f]{64}$"#),
        // Zahlung, Kommunikation, Werkzeuge
        Rule(kind: "Stripe-Schlüssel", pattern: #"^(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,247}$"#),
        Rule(kind: "Stripe-Webhook-Geheimnis", pattern: #"^whsec_[A-Za-z0-9]{32,}$"#),
        Rule(kind: "Shopify-Token", pattern: #"^shp(?:at|ca|pa|ss)_[0-9a-fA-F]{32}$"#),
        Rule(kind: "Slack-Token", pattern: #"^xox(?:[abposr]|e(?:\.xox[bp])?)-[0-9A-Za-z-]{10,250}$"#),
        Rule(kind: "Slack-App-Token", pattern: #"^xapp-[0-9]-[A-Z0-9]+-[0-9]+-[a-z0-9]+$"#),
        Rule(kind: "Slack-Webhook", pattern: #"^https://hooks\.slack\.com/(?:services|workflows|triggers)/[A-Za-z0-9+/]{43,56}$"#),
        Rule(kind: "SendGrid-Schlüssel", pattern: #"^SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}$"#),
        Rule(kind: "Mailgun-Schlüssel", pattern: #"^key-[0-9a-f]{32}$"#),
        Rule(kind: "Brevo-Schlüssel", pattern: #"^xkeysib-[0-9a-f]{64}-[A-Za-z0-9]{16}$"#),
        Rule(kind: "Telegram-Bot-Token", pattern: #"^[0-9]{5,16}:A[A-Za-z0-9_-]{34}$"#),
        Rule(kind: "Notion-Token", pattern: #"^(?:ntn_[0-9]{11}[A-Za-z0-9]{35}|secret_[A-Za-z0-9]{43})$"#),
        Rule(kind: "Linear-Schlüssel", pattern: #"^lin_api_[A-Za-z0-9]{40}$"#),
        Rule(kind: "Atlassian-Token", pattern: #"^ATATT3[A-Za-z0-9_=-]{186}$"#),
        Rule(kind: "1Password-Dienstkonto", pattern: #"^ops_eyJ[A-Za-z0-9+/]{250,}={0,3}$"#),
        Rule(kind: "1Password-Geheimschlüssel", pattern: #"^A3-[A-Z0-9]{6}-(?:[A-Z0-9]{11}|[A-Z0-9]{6}-[A-Z0-9]{5})-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$"#),
        // Struktur statt Anbieter – zuletzt.
        Rule(kind: "Privater Schlüssel", pattern: #"^-----BEGIN[ A-Z0-9_-]{0,100}PRIVATE KEY(?: BLOCK)?-----[\s\S]{64,}?-----END[ A-Z0-9_-]{0,100}PRIVATE KEY(?: BLOCK)?-----$"#),
        Rule(kind: "JWT-Token", pattern: #"^eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]*$"#),
    ]
    // swiftlint:enable line_length

    private static let compiled: [(kind: String, regex: NSRegularExpression)] = rules.compactMap { rule in
        (try? NSRegularExpression(pattern: rule.pattern)).map { (rule.kind, $0) }
    }

    static func kind(of payload: ClipPayload) -> String? { kind(of: payload.plain) }

    static func kind(of text: String) -> String? {
        guard text.utf8.count <= maxBytes else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for rule in compiled {
            if let match = rule.regex.firstMatch(in: trimmed, options: [.anchored], range: range),
               match.range == range {
                return rule.kind
            }
        }
        return nil
    }
}
