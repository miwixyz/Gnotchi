import Foundation

/// Titel-Vorschläge für Tresor-Einträge (G39) aus einem festen Präfix-Katalog. Läuft nur im Speicher; weder Wert
/// noch Präfix erscheinen je in Protokoll oder Fehlertext.
enum VaultTitles {
    /// Reihenfolge zählt: längere Präfixe zuerst (`sk-ant-` vor `sk-`).
    static let catalog: [(prefix: String, title: String)] = [
        ("sk-ant-", "Anthropic"),
        ("sk-proj-", "OpenAI"),
        ("sk-or-", "OpenRouter"),
        ("sk_live_", "Stripe (live)"),
        ("sk_test_", "Stripe (Test)"),
        ("pk_live_", "Stripe öffentlich (live)"),
        ("ghp_", "GitHub"),
        ("github_pat_", "GitHub"),
        ("glpat-", "GitLab"),
        ("xoxb-", "Slack"),
        ("AIza", "Google"),
        ("AKIA", "AWS"),
        ("hf_", "Hugging Face"),
        ("gsk_", "Groq"),
        ("pplx-", "Perplexity"),
        ("re_", "Resend"),
        ("fc-", "Firecrawl"),
        ("sk-", "API-Schlüssel"),
    ]

    static func suggest(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.first { trimmed.hasPrefix($0.prefix) }?.title ?? String(localized: "Eintrag")
    }
}
