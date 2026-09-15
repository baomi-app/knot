import Foundation

enum UpdateFeedAvailability {
    /// This is only an availability check. Sparkle still downloads and verifies
    /// the signed feed and archive before it can offer or install any update.
    static func issue(at url: URL, session: URLSession = .shared) async -> String? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                return "The update server returned an unexpected response. Please try again later."
            }
            return issue(forHTTPStatus: response.statusCode)
        } catch {
            return "Could not reach the update server. Check your connection and try again."
        }
    }

    static func issue(forHTTPStatus status: Int) -> String? {
        switch status {
        case 200..<300, 405, 501:
            // Some hosts do not implement HEAD. Let Sparkle perform its normal
            // GET and signature verification instead of rejecting those hosts.
            return nil
        case 404:
            return "Update information is unavailable (HTTP 404). The update feed needs to be published with a release."
        default:
            return "The update server returned HTTP \(status). Please try again later."
        }
    }
}
