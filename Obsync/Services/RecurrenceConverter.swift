import Foundation
import EventKit

/// Bidirectional converter between Obsidian Tasks recurrence rule strings and
/// `EKRecurrenceRule` (the native Apple Reminders recurrence model).
///
/// Obsidian Tasks plugin grammar we handle:
///   - `🔁 every day`                            → daily, interval 1
///   - `🔁 every N days`                         → daily, interval N
///   - `🔁 every week`                           → weekly, interval 1
///   - `🔁 every N weeks`                        → weekly, interval N
///   - `🔁 every month`                          → monthly, interval 1
///   - `🔁 every N months`                       → monthly, interval N
///   - `🔁 every month on the Nth`               → monthly, interval 1, daysOfTheMonth=[N]
///   - `🔁 every year`                           → yearly, interval 1
///   - `🔁 every N years`                        → yearly, interval N
///
/// The emoji prefix (🔁 or 🔂, optionally followed by the FE0F variation
/// selector) is optional. A `when done` suffix is preserved on format but
/// does not affect the EKRecurrenceRule (Apple has no equivalent — it always
/// rolls from the completion date).
///
/// Unparseable rules return `nil` on `parse(...)` so the caller can fall back
/// to the text-only completion-driven model rather than producing a bogus
/// EKRecurrenceRule. See #57 Phase B.
enum RecurrenceConverter {

    // MARK: - Parse: Obsidian string → EKRecurrenceRule

    /// Parse an Obsidian Tasks recurrence rule string. Returns `nil` for
    /// grammars we don't handle yet (callers should keep their text copy
    /// and continue with the Phase-A completion-driven flow).
    static func parse(ruleText: String) -> EKRecurrenceRule? {
        let normalized = normalize(ruleText)
        guard !normalized.isEmpty else { return nil }

        // Extract leading "every [N] <unit>" pattern. The rest of the line may
        // carry extra info (e.g. "on the 15th") that we handle below.
        let regex = try? NSRegularExpression(
            pattern: #"^every\s+(?:(\d+)\s+)?(day|days|week|weeks|month|months|year|years)\b(.*)$"#,
            options: [.caseInsensitive]
        )
        guard let regex = regex else { return nil }
        let range = NSRange(normalized.startIndex..., in: normalized)
        guard let match = regex.firstMatch(in: normalized, options: [], range: range),
              match.numberOfRanges >= 4 else {
            return nil
        }

        let interval: Int = {
            guard let intervalRange = Range(match.range(at: 1), in: normalized),
                  let n = Int(normalized[intervalRange]) else { return 1 }
            return max(1, n)
        }()

        guard let unitRange = Range(match.range(at: 2), in: normalized) else { return nil }
        let unit = String(normalized[unitRange]).lowercased()
        let tail = Range(match.range(at: 3), in: normalized)
            .map { String(normalized[$0]) } ?? ""

        let frequency: EKRecurrenceFrequency
        switch unit {
        case "day", "days":     frequency = .daily
        case "week", "weeks":   frequency = .weekly
        case "month", "months": frequency = .monthly
        case "year", "years":   frequency = .yearly
        default: return nil
        }

        // Parse tail modifiers (currently: "on the Nth" for monthly).
        // NSNumber instances are what EKRecurrenceRule expects.
        var daysOfTheMonth: [NSNumber]? = nil
        if frequency == .monthly {
            if let dom = parseDayOfMonth(from: tail) {
                daysOfTheMonth = [NSNumber(value: dom)]
            }
        }

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: interval,
            daysOfTheWeek: nil,
            daysOfTheMonth: daysOfTheMonth,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
    }

    // MARK: - Format: EKRecurrenceRule → Obsidian string

    /// Generate an Obsidian-style rule string from an `EKRecurrenceRule`.
    /// Returns a canonical form prefixed with 🔁 so round-trips are stable.
    /// Returns `nil` for shapes we can't express in the plugin's grammar
    /// (e.g. set positions, complex byday rules).
    static func format(rule: EKRecurrenceRule) -> String? {
        let interval = max(1, rule.interval)

        switch rule.frequency {
        case .daily:
            return "🔁 " + (interval == 1 ? "every day" : "every \(interval) days")

        case .weekly:
            // We don't yet serialize daysOfTheWeek — if set, fall back to generic
            // "every N weeks" text. The plugin will still keep the rule on screen
            // via our verbatim text preservation in Phase A.
            return "🔁 " + (interval == 1 ? "every week" : "every \(interval) weeks")

        case .monthly:
            if let days = rule.daysOfTheMonth, let first = days.first, interval == 1 {
                return "🔁 every month on the \(ordinal(first.intValue))"
            }
            return "🔁 " + (interval == 1 ? "every month" : "every \(interval) months")

        case .yearly:
            return "🔁 " + (interval == 1 ? "every year" : "every \(interval) years")

        @unknown default:
            return nil
        }
    }

    // MARK: - Equality helpers

    /// Compare two Obsidian rule strings semantically (after normalization
    /// + parse + reformat). Used by the re-linking logic to match a reminder
    /// to its Obsidian twin when the IDs don't line up yet.
    static func rulesAreEquivalent(_ a: String?, _ b: String?) -> Bool {
        let na = a.map(normalize) ?? ""
        let nb = b.map(normalize) ?? ""
        if na.isEmpty && nb.isEmpty { return true }
        if na == nb { return true }
        guard let ra = parse(ruleText: na), let rb = parse(ruleText: nb) else {
            return false
        }
        return ra.frequency == rb.frequency
            && ra.interval == rb.interval
            && (ra.daysOfTheMonth ?? []) == (rb.daysOfTheMonth ?? [])
    }

    // MARK: - Private helpers

    /// Strip emoji prefix + FE0F variation selector + "when done" suffix.
    /// Collapse whitespace so regex matching is predictable.
    private static func normalize(_ raw: String) -> String {
        var s = raw
        // Strip 🔁/🔂 optionally followed by FE0F.
        s = s.replacingOccurrences(of: "🔁\u{FE0F}", with: "")
        s = s.replacingOccurrences(of: "🔂\u{FE0F}", with: "")
        s = s.replacingOccurrences(of: "🔁", with: "")
        s = s.replacingOccurrences(of: "🔂", with: "")
        // Strip "when done" — we don't have an EKRecurrenceRule field for it,
        // and Apple always rolls from the completion date anyway.
        if let whenRange = s.range(of: "when done", options: [.caseInsensitive]) {
            s.removeSubrange(whenRange)
        }
        // Collapse whitespace.
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.lowercased()
    }

    /// Extract the day-of-month number from strings like "on the 15th" or
    /// "on the 1st". Returns `nil` if no match.
    private static func parseDayOfMonth(from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\bon\s+the\s+(\d+)(?:st|nd|rd|th)?\b"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let dayRange = Range(match.range(at: 1), in: text),
              let day = Int(text[dayRange]) else { return nil }
        guard (1...31).contains(day) else { return nil }
        return day
    }

    /// Render an ordinal suffix: 1 → "1st", 2 → "2nd", 3 → "3rd", 4 → "4th"…
    /// 11/12/13 all get "th".
    private static func ordinal(_ n: Int) -> String {
        let mod100 = n % 100
        if (11...13).contains(mod100) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }
}
