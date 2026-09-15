import Foundation
import XCTest

final class UpdateFeedAvailabilityTests: XCTestCase {
    func testAvailableFeedContinuesToSparkleVerification() {
        XCTAssertNil(UpdateFeedAvailability.issue(forHTTPStatus: 200))
        XCTAssertNil(UpdateFeedAvailability.issue(forHTTPStatus: 204))
    }

    func testMissingFeedExplainsPublicationProblem() {
        let message = UpdateFeedAvailability.issue(forHTTPStatus: 404)
        XCTAssertTrue(message?.contains("404") == true)
        XCTAssertTrue(message?.contains("published") == true)
    }

    func testServersWithoutHeadSupportStillUseSparkle() {
        XCTAssertNil(UpdateFeedAvailability.issue(forHTTPStatus: 405))
        XCTAssertNil(UpdateFeedAvailability.issue(forHTTPStatus: 501))
    }

    func testOtherHTTPFailuresAreNotMisreportedAsUnpublishedFeed() {
        for status in [403, 429, 500, 503] {
            let message = UpdateFeedAvailability.issue(forHTTPStatus: status)
            XCTAssertTrue(message?.contains(String(status)) == true)
            XCTAssertFalse(message?.contains("published") == true)
        }
    }

    func testProbeUsesHeadAndReports404WithoutDownloadingUpdateContent() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MissingFeedProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let message = await UpdateFeedAvailability.issue(
            at: URL(string: "https://example.test/appcast.xml")!,
            session: session
        )
        XCTAssertEqual(message, UpdateFeedAvailability.issue(forHTTPStatus: 404))
    }
}

private final class MissingFeedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard request.httpMethod == "HEAD", let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
