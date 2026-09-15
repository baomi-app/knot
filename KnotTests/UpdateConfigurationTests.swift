import Foundation
import XCTest

final class UpdateConfigurationTests: XCTestCase {
    // A structural fixture only, never used to sign or configure a real build.
    private var validConfiguration: [String: Any] {
        [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
            "SUVerifyUpdateBeforeExtraction": true,
            "SURequireSignedFeed": true
        ]
    }

    func testAcceptsSecureConfiguration() {
        XCTAssertNil(UpdateConfiguration.issue(in: validConfiguration))
    }

    func testRejectsMissingOrInsecureFeed() {
        var configuration = validConfiguration
        configuration.removeValue(forKey: "SUFeedURL")
        XCTAssertNotNil(UpdateConfiguration.issue(in: configuration))

        for feed in ["", "appcast.xml", "http://example.com/appcast.xml", "file:///tmp/appcast.xml", "https://user:password@example.com/appcast.xml"] {
            configuration["SUFeedURL"] = feed
            XCTAssertNotNil(UpdateConfiguration.issue(in: configuration), feed)
        }
    }

    func testRejectsMissingMalformedOrWrongLengthKey() {
        var configuration = validConfiguration
        configuration.removeValue(forKey: "SUPublicEDKey")
        XCTAssertNotNil(UpdateConfiguration.issue(in: configuration))

        for key in ["", "not a key", Data(repeating: 7, count: 31).base64EncodedString(), Data(repeating: 7, count: 33).base64EncodedString()] {
            configuration["SUPublicEDKey"] = key
            XCTAssertNotNil(UpdateConfiguration.issue(in: configuration))
        }
    }

    func testRequiresSignedFeedAndPreExtractionVerification() {
        for setting in ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"] {
            var configuration = validConfiguration
            configuration.removeValue(forKey: setting)
            XCTAssertNotNil(UpdateConfiguration.issue(in: configuration))
            configuration[setting] = false
            XCTAssertNotNil(UpdateConfiguration.issue(in: configuration))
        }
    }
}
