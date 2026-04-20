import XCTest
@testable import Remindian

/// Unit tests for Things3Destination's AppleScript property construction.
///
/// We don't drive NSAppleScript here (Things 3 isn't available in CI); we verify the
/// AppleScript text that would be passed to it. The critical invariant is #59:
/// `tag names` must be a comma-separated STRING, not an AppleScript list.
final class Things3DestinationTests: XCTestCase {

    // MARK: - #59 tag names must be text, not a list

    /// Regression test: with 2+ tags we must emit `tag names:"a, b"`, never
    /// `tag names:{"a", "b"}`. Things 3's scripting dictionary declares `tag names`
    /// as TEXT, so list syntax fails AppleScript coercion with error -1700.
    func testBuildTagNamesPropertyMultipleTags_usesCommaSeparatedString() {
        let dest = Things3Destination()
        let result = dest.buildTagNamesProperty(tags: ["#work", "#urgent"])

        XCTAssertEqual(result, "tag names:\"work, urgent\"")
        XCTAssertFalse(result.contains("{"), "Must not use AppleScript list syntax `{…}` — breaks Things 3 with -1700 when 2+ tags (#59)")
        XCTAssertFalse(result.contains("}"), "Must not use AppleScript list syntax `{…}` — breaks Things 3 with -1700 when 2+ tags (#59)")
    }

    /// Single tag case still works — this path previously coerced by accident in list form,
    /// string form is correct either way.
    func testBuildTagNamesPropertySingleTag_usesString() {
        let dest = Things3Destination()
        let result = dest.buildTagNamesProperty(tags: ["#work"])

        XCTAssertEqual(result, "tag names:\"work\"")
        XCTAssertFalse(result.contains("{"))
    }

    func testBuildTagNamesPropertyEmptyTags_returnsEmptyString() {
        let dest = Things3Destination()
        XCTAssertEqual(dest.buildTagNamesProperty(tags: []), "")
    }

    /// Hash prefixes should be stripped per cleanTagsForThings.
    func testBuildTagNamesPropertyStripsHashPrefix() {
        let dest = Things3Destination()
        let result = dest.buildTagNamesProperty(tags: ["#work", "personal"])
        XCTAssertEqual(result, "tag names:\"work, personal\"")
    }

    /// Hierarchical tags (`person/name`) should be reduced to leaf (`name`) — Things 3
    /// URL scheme and scripting dictionary require exact tag match by leaf name.
    func testBuildTagNamesPropertyExtractsLeafFromHierarchical() {
        let dest = Things3Destination()
        let result = dest.buildTagNamesProperty(tags: ["#person/alice", "#project/x"])
        XCTAssertEqual(result, "tag names:\"alice, x\"")
    }

    /// Duplicates after leaf extraction should be deduped.
    func testBuildTagNamesPropertyDedupsDuplicates() {
        let dest = Things3Destination()
        let result = dest.buildTagNamesProperty(tags: ["#work", "#work", "#urgent"])
        XCTAssertEqual(result, "tag names:\"work, urgent\"")
    }

    /// Quote characters in tag names must be escaped so they don't close the AppleScript
    /// string literal prematurely. (Uncommon but defensive.)
    func testBuildTagNamesPropertyEscapesQuotes() {
        let dest = Things3Destination()
        let result = dest.buildTagNamesProperty(tags: ["she\"said"])
        XCTAssertEqual(result, "tag names:\"she\\\"said\"")
    }
}
