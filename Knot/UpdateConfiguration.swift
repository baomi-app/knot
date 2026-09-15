import Foundation

enum UpdateConfiguration {
    static func issue(in info: [String: Any]) -> String? {
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed),
              url.scheme == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil else {
            return "This build does not have a secure update feed configured."
        }
        guard let encodedKey = info["SUPublicEDKey"] as? String,
              let key = Data(base64Encoded: encodedKey), key.count == 32 else {
            return "This build does not have an update verification key configured."
        }
        guard info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              info["SURequireSignedFeed"] as? Bool == true else {
            return "This build does not have signed update verification enabled."
        }
        return nil
    }
}
