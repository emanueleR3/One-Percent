import XCTest
@testable import OnePercentCore

/// The Supabase project comes from build settings (Config/Local.xcconfig via the Info.plist), so it
/// must survive the ways those values arrive: a bare host, a full URL, or nothing at all.
final class SupabaseConfigTests: XCTestCase {
    func testABareHostBecomesAnHTTPSURL() throws {
        let config = try XCTUnwrap(SupabaseConfig.make(host: "abcd.supabase.co", key: "sb_publishable_x"))
        XCTAssertEqual(config.url.absoluteString, "https://abcd.supabase.co")
        XCTAssertEqual(config.publishableKey, "sb_publishable_x")
        XCTAssertEqual(config.endpoint("rest/v1/sync_records").absoluteString, "https://abcd.supabase.co/rest/v1/sync_records")
    }

    func testAFullURLIsKept() throws {
        let config = try XCTUnwrap(SupabaseConfig.make(host: " http://127.0.0.1:54321 ", key: " key "))
        XCTAssertEqual(config.url.absoluteString, "http://127.0.0.1:54321")
        XCTAssertEqual(config.publishableKey, "key")
    }

    func testMissingValuesTurnSyncOff() {
        XCTAssertNil(SupabaseConfig.make(host: nil, key: nil))
        XCTAssertNil(SupabaseConfig.make(host: "", key: "sb_publishable_x"))
        XCTAssertNil(SupabaseConfig.make(host: "abcd.supabase.co", key: "   "))
    }

    func testUnexpandedOrCutOffSettingsAreRefused() {
        XCTAssertNil(SupabaseConfig.make(host: "$(ONEPERCENT_SUPABASE_HOST)", key: "sb_publishable_x"))
        XCTAssertNil(SupabaseConfig.make(host: "abcd.supabase.co", key: "$(ONEPERCENT_SUPABASE_KEY)"))
        // "https://abcd.supabase.co" in an .xcconfig file: Xcode reads "//" as a comment.
        XCTAssertNil(SupabaseConfig.make(host: "https:", key: "sb_publishable_x"))
        XCTAssertNil(SupabaseConfig.make(host: "ftp://abcd.supabase.co", key: "sb_publishable_x"))
    }

    func testABundleWithoutTheKeysHasNoProject() {
        // The test runner's bundle has no OnePercentSupabase* keys.
        XCTAssertNil(SupabaseConfig.fromBundle(Bundle(for: Self.self)))
    }
}
