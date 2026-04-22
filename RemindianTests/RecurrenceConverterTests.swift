import XCTest
import EventKit
@testable import Remindian

/// Unit tests for `RecurrenceConverter` — the Obsidian rule ↔ EKRecurrenceRule
/// bridge introduced in #57 Phase B.
final class RecurrenceConverterTests: XCTestCase {

    // MARK: - Parse: Obsidian string → EKRecurrenceRule

    func testParseEveryDay() {
        let rule = RecurrenceConverter.parse(ruleText: "🔁 every day")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .daily)
        XCTAssertEqual(rule?.interval, 1)
    }

    func testParseEveryNDaysWithInterval() {
        let rule = RecurrenceConverter.parse(ruleText: "🔁 every 3 days")
        XCTAssertEqual(rule?.frequency, .daily)
        XCTAssertEqual(rule?.interval, 3)
    }

    func testParseEveryWeek() {
        let rule = RecurrenceConverter.parse(ruleText: "every week")
        XCTAssertEqual(rule?.frequency, .weekly)
        XCTAssertEqual(rule?.interval, 1)
    }

    func testParseEvery2Weeks() {
        let rule = RecurrenceConverter.parse(ruleText: "🔁 every 2 weeks")
        XCTAssertEqual(rule?.frequency, .weekly)
        XCTAssertEqual(rule?.interval, 2)
    }

    func testParseEveryMonth() {
        let rule = RecurrenceConverter.parse(ruleText: "🔁 every month")
        XCTAssertEqual(rule?.frequency, .monthly)
        XCTAssertEqual(rule?.interval, 1)
        XCTAssertNil(rule?.daysOfTheMonth)
    }

    func testParseEveryMonthOnTheNth() {
        let rule = RecurrenceConverter.parse(ruleText: "🔁 every month on the 15th")
        XCTAssertEqual(rule?.frequency, .monthly)
        XCTAssertEqual(rule?.interval, 1)
        XCTAssertEqual(rule?.daysOfTheMonth, [NSNumber(value: 15)])
    }

    func testParseEveryMonthOnThe1st() {
        let rule = RecurrenceConverter.parse(ruleText: "every month on the 1st")
        XCTAssertEqual(rule?.daysOfTheMonth, [NSNumber(value: 1)])
    }

    func testParseEveryYear() {
        let rule = RecurrenceConverter.parse(ruleText: "🔁 every year")
        XCTAssertEqual(rule?.frequency, .yearly)
        XCTAssertEqual(rule?.interval, 1)
    }

    /// The "when done" suffix doesn't have an EKRecurrenceRule equivalent
    /// (Apple always rolls from completion date) but it must be tolerated.
    func testParseIgnoresWhenDoneSuffix() {
        let rule = RecurrenceConverter.parse(ruleText: "🔁 every week when done")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .weekly)
    }

    /// FE0F is the variation selector some emoji keyboards inject after 🔁.
    /// Must not break parsing.
    func testParseToleratesFE0FVariationSelector() {
        let rule = RecurrenceConverter.parse(ruleText: "🔁\u{FE0F} every 2 days")
        XCTAssertEqual(rule?.frequency, .daily)
        XCTAssertEqual(rule?.interval, 2)
    }

    func testParseReturnsNilForUnsupported() {
        XCTAssertNil(RecurrenceConverter.parse(ruleText: "every blue moon"))
        XCTAssertNil(RecurrenceConverter.parse(ruleText: ""))
        XCTAssertNil(RecurrenceConverter.parse(ruleText: "🔁"))
    }

    // MARK: - Format: EKRecurrenceRule → Obsidian string

    func testFormatDailyInterval1() {
        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        XCTAssertEqual(RecurrenceConverter.format(rule: rule), "🔁 every day")
    }

    func testFormatDailyIntervalN() {
        let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 5, end: nil)
        XCTAssertEqual(RecurrenceConverter.format(rule: rule), "🔁 every 5 days")
    }

    func testFormatWeekly() {
        let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        XCTAssertEqual(RecurrenceConverter.format(rule: rule), "🔁 every week")
    }

    func testFormatMonthlyOnTheNth() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .monthly,
            interval: 1,
            daysOfTheWeek: nil,
            daysOfTheMonth: [NSNumber(value: 15)],
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
        XCTAssertEqual(RecurrenceConverter.format(rule: rule), "🔁 every month on the 15th")
    }

    func testFormatMonthlyOrdinalSuffixes() {
        // Spot-check the ordinal suffixer for the edge cases.
        let cases: [(Int, String)] = [
            (1, "1st"), (2, "2nd"), (3, "3rd"), (4, "4th"),
            (11, "11th"), (12, "12th"), (13, "13th"),
            (21, "21st"), (22, "22nd"), (23, "23rd"),
            (31, "31st")
        ]
        for (day, expectedSuffix) in cases {
            let rule = EKRecurrenceRule(
                recurrenceWith: .monthly, interval: 1,
                daysOfTheWeek: nil,
                daysOfTheMonth: [NSNumber(value: day)],
                monthsOfTheYear: nil, weeksOfTheYear: nil,
                daysOfTheYear: nil, setPositions: nil, end: nil
            )
            let formatted = RecurrenceConverter.format(rule: rule)
            XCTAssertEqual(formatted, "🔁 every month on the \(expectedSuffix)")
        }
    }

    func testFormatYearly() {
        let rule = EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        XCTAssertEqual(RecurrenceConverter.format(rule: rule), "🔁 every year")
    }

    // MARK: - Round-trip stability

    /// Values we export must parse back to the same semantic rule — otherwise
    /// every sync would detect a spurious change.
    func testRoundTripDaily() {
        roundTripCheck("🔁 every day", frequency: .daily, interval: 1)
        roundTripCheck("🔁 every 3 days", frequency: .daily, interval: 3)
    }

    func testRoundTripWeekly() {
        roundTripCheck("🔁 every week", frequency: .weekly, interval: 1)
        roundTripCheck("🔁 every 2 weeks", frequency: .weekly, interval: 2)
    }

    func testRoundTripMonthly() {
        roundTripCheck("🔁 every month", frequency: .monthly, interval: 1)
    }

    func testRoundTripMonthlyOnTheNth() {
        guard let original = RecurrenceConverter.parse(ruleText: "🔁 every month on the 15th") else {
            XCTFail("failed to parse original rule")
            return
        }
        let formatted = RecurrenceConverter.format(rule: original)
        XCTAssertEqual(formatted, "🔁 every month on the 15th")
        let reparsed = RecurrenceConverter.parse(ruleText: formatted ?? "")
        XCTAssertEqual(reparsed?.frequency, .monthly)
        XCTAssertEqual(reparsed?.interval, 1)
        XCTAssertEqual(reparsed?.daysOfTheMonth, [NSNumber(value: 15)])
    }

    // MARK: - Semantic equivalence (used by re-linking heuristic)

    func testRulesAreEquivalentIdenticalText() {
        XCTAssertTrue(RecurrenceConverter.rulesAreEquivalent("🔁 every week", "🔁 every week"))
    }

    func testRulesAreEquivalentDifferentFormatSameMeaning() {
        XCTAssertTrue(RecurrenceConverter.rulesAreEquivalent("every week", "🔁 every week"))
        XCTAssertTrue(RecurrenceConverter.rulesAreEquivalent("🔁 every week when done", "every week"))
    }

    func testRulesNotEquivalentDifferentFrequency() {
        XCTAssertFalse(RecurrenceConverter.rulesAreEquivalent("every week", "every month"))
    }

    func testRulesNotEquivalentDifferentInterval() {
        XCTAssertFalse(RecurrenceConverter.rulesAreEquivalent("every 2 weeks", "every 3 weeks"))
    }

    func testRulesEquivalentBothNil() {
        XCTAssertTrue(RecurrenceConverter.rulesAreEquivalent(nil, nil))
    }

    func testRulesNotEquivalentOneNil() {
        XCTAssertFalse(RecurrenceConverter.rulesAreEquivalent("every week", nil))
        XCTAssertFalse(RecurrenceConverter.rulesAreEquivalent(nil, "every week"))
    }

    // MARK: - Helpers

    private func roundTripCheck(_ rule: String, frequency: EKRecurrenceFrequency, interval: Int) {
        guard let parsed = RecurrenceConverter.parse(ruleText: rule) else {
            XCTFail("Failed to parse '\(rule)'")
            return
        }
        XCTAssertEqual(parsed.frequency, frequency)
        XCTAssertEqual(parsed.interval, interval)

        guard let formatted = RecurrenceConverter.format(rule: parsed) else {
            XCTFail("Failed to format parsed '\(rule)'")
            return
        }
        guard let reparsed = RecurrenceConverter.parse(ruleText: formatted) else {
            XCTFail("Failed to re-parse formatted '\(formatted)'")
            return
        }
        XCTAssertEqual(reparsed.frequency, frequency)
        XCTAssertEqual(reparsed.interval, interval)
    }
}
